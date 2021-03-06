local CONFIG = require "MyConfig"

local QUIT, signal_handler = false
signal_handler = function(premature)
    if premature then
        QUIT = true
        ngx.log(ngx.ERR, "nginx is stopping or reloading...")
        return
    end
    QUIT = false
    ngx.log(ngx.ERR, "nginx worker "..ngx.worker.pid().." is running...")
    ngx.timer.at(10 * 60, signal_handler)
end
ngx.timer.at(0, signal_handler)


local register_center = require(CONFIG.REGISTER_CENTER)
local get_datacenter_config = register_center.get_datacenter_config
local get_upstream_config = register_center.get_upstream_config
local get_blacklist_config = register_center.get_blacklist_config

local _get_config = function()
    local status, dc_config, code, msg = pcall(get_datacenter_config)
    if status and dc_config then
        CONFIG.DC_CACHE:set(CONFIG.DC_CACHE_KEY, dc_config)
        local status, up_config, code, msg = pcall(
            get_upstream_config, dc_config)
        if status and up_config then
            --ngx.log(ngx.ERR, "up_config")
            CONFIG.UPSTREAM_CACHE:set(CONFIG.UPSTREAM_CACHE_KEY, up_config)
        end

        local status, blacklist_config, code, msg = pcall(
            get_blacklist_config, dc_config)
        if status and blacklist_config then
            CONFIG.BLACKLIST_CACHE:set(CONFIG.BLACKLIST_CACHE_KEY,
                blacklist_config)
        end
    end
end

if true then
    local get_config

    get_config = function(premature)
        if premature then return end

        local lock, code, err = CONFIG.UPSTREAMS_LOCK(false)
        if lock then
            pcall(_get_config)
            CONFIG.UPSTREAMS_LOCK(true)
        end

        ngx.timer.at(CONFIG.POLL_INTERVAL, get_config)
    end

    ngx.timer.at(0, get_config)
end

if type(CONFIG.HEALTH_CHECK_MODULE) == "string" then
    local health_check
    local HEALTH_CHECK = require(CONFIG.HEALTH_CHECK_MODULE)

    health_check = function(premature)
        if premature then return end

        local up_config = CONFIG.UPSTREAM_CACHE:get(
            CONFIG.UPSTREAM_CACHE_KEY)
        if up_config then
            local upstreams = {}
            for dc, dc_upstreams in pairs(up_config) do
                for _, upstream in pairs(dc_upstreams) do
                    table.insert(upstreams, upstream)
                end
            end
            if #upstreams > 0 then
                HEALTH_CHECK.execute_health_check(upstreams)
            end
        end
        ngx.timer.at(CONFIG.HEALTH_CHECK_POLL_INTERVAL, health_check)
    end

    ngx.timer.at(0, health_check)
end

if type(CONFIG.ADVICE_CENTER) == "string" then 
    local advice_center = require(CONFIG.ADVICE_CENTER)

    local hold_advice = function(premature)
        if premature then return end

        local advice_center_hold = advice_center.hold()
        while true do
            if QUIT then
                advice_center_hold(false)
                ngx.log(ngx.ERR, "QUIT is "..tostring(QUIT))
                break
            end

            local message_type, err = advice_center_hold(true)
            if message_type then
                ngx.log(ngx.ERR, "message_type: "..message_type)
                local lock, code, err = CONFIG.UPSTREAMS_LOCK(false)
                if lock then
                    pcall(_get_config)
                    CONFIG.UPSTREAMS_LOCK(true)
                end
            elseif err == "timeout" then
                local _ = false -- just a NULL STATEMENT
            else
                ngx.sleep(CONFIG.REDIS_ADVICE_RECONNECT_DELAY)
            end
        end
    end

    ngx.timer.at(0, hold_advice)
end

