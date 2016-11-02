local CONFIG = require "MyConfig"
local HEALTH_CHECK = require "HealthCheck"
local register_center = require(CONFIG.REGISTER_CENTER)
local get_datacenter_config = register_center.get_datacenter_config
local get_upstream_config = register_center.get_upstream_config
local advice_center = require(CONFIG.ADVICE_CENTER)

local get_config, health_check, _get_config, hold_advice

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
        HEALTH_CHECK.execute_health_check(upstreams)
    end
    ngx.timer.at(CONFIG.HEALTH_CHECK_POLL_INTERVAL, health_check)
end

_get_config = function()
    local status, dc_config, code, msg = pcall(get_datacenter_config)
    if status and dc_config then
        CONFIG.DC_CACHE:set(CONFIG.DC_CACHE_KEY, dc_config)
        local status, up_config, code, msg = pcall(
            get_upstream_config, dc_config)
        if status and up_config then
            --ngx.log(ngx.ERR, "up_config")
            CONFIG.UPSTREAM_CACHE:set(CONFIG.UPSTREAM_CACHE_KEY, up_config)
        end
    end
end

get_config = function(premature)
    if premature then return end

    local lock, code, err = CONFIG.UPSTREAMS_LOCK(false)
    if lock then
        pcall(_get_config)
        CONFIG.UPSTREAMS_LOCK(true)
    end

    ngx.timer.at(CONFIG.POLL_INTERVAL, get_config)
end

hold_advice = function(premature)
    if premature then return end

    local advice_center_hold = advice_center.hold()
    while true do
        message_type = advice_center_hold(true)
        ngx.log(ngx.ERR, "message_type: "..message_type)
        local lock, code, err = CONFIG.UPSTREAMS_LOCK(false)
        if lock then
            pcall(_get_config)
            CONFIG.UPSTREAMS_LOCK(true)
        end
    end
end

ngx.timer.at(0, get_config)
ngx.timer.at(0, health_check)
ngx.timer.at(0, hold_advice)

