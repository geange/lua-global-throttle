local typedefs = require "kong.db.schema.typedefs"
local types = require "kong.plugins.request-throttle.types"

local type = type
--- Validates value of `sentinel_addresses` field.
local function check_redis_sentinel_addresses(values)
    if type(values) == "table" then
        for _, value in ipairs(values) do
            local server = types.sentinel_addresses(value)
            if not server then
                return false, "invalid sentinel_addresses server value: " .. value
            end
        end
        return true
    end
    return false, "sentinel_addresses is required"
end

local function check_has_define_shared_dict(dict)
    if not ngx.shared[dict] then
        return false,
        "missing shared dict '" .. dict .. "' in Nginx " ..
                "configuration, are you using a custom template? " ..
                "Make sure the 'lua_shared_dict " .. dict .. " [SIZE];' " ..
                "directive is defined."
    end
    return true
end

return {
    name = "request-throttle",
    fields = {
        { consumer = typedefs.no_consumer },
        { protocols = typedefs.protocols_http },
        { config = {
            type = "record",
            fields = {
                { limit = { type = "integer", required = true, gt = 0, }, },
                { window_size_in_seconds = { type = "integer", required = true, gt = 0, }, },
                { limit_by = {
                    type = "string",
                    default = "current_entity",
                    one_of = { "uri", "current_entity", "ip" },
                }, },
                { sync_rate = { type = "integer", required = true, default = 1, gt = 0, }, },
                {
                    strategy = {
                        type = "string",
                        default = "redis",
                        len_min = 0,
                        one_of = { "redis", "redis-sentinel" },
                    }, },
                { counter_dict = { type = "string", required = true, default = "request_throttle_counter" }, },
                { uuid = typedefs.uuid, },
                { redis = {
                    type = "record",
                    fields = {
                        { host = typedefs.host, },
                        { port = typedefs.port({ default = 6379 }), },
                        { timeout = { type = "number", required = true, default = 2000, }, },
                        { password = { type = "string", }, },
                        { database = { type = "number", required = true }, },
                        { sentinel_master = { type = "string", }, },
                        { sentinel_role = { type = "string", default = "master" }, },
                        { sentinel_addresses = { type = "array", elements = { type = "string" }, required = false }, },
                        --????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????? TIME_WAIT
                        --???????????????????????? Linux ????????? 2 ????????? ??????agentzh???
                        { max_idle_timeout = { type = "number", default = 30000 }, },
                        --?????????????????????????????? nginx worker ?????????????????????????????????????????????????????????????????? worker ????????????????????????
                        --10????????????????????? 10 ?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????agentzh
                        { pool_size = { type = "number", default = 3 }, },
                    },
                },
                },
            },
        },
        },
    },
    entity_checks = {
        { conditional = {
            if_field = "config.strategy", if_match = { eq = "redis" },
            then_field = "config.redis.host", then_match = { required = true },
        } },
        { conditional = {
            if_field = "config.strategy", if_match = { eq = "redis" },
            then_field = "config.redis.port", then_match = { required = true },
        } },
        { conditional = {
            if_field = "config.strategy", if_match = { eq = "redis-sentinel" },
            then_field = "config.redis.sentinel_master", then_match = { required = true },
        } },
        { conditional = {
            if_field = "config.strategy", if_match = { eq = "redis-sentinel" },
            then_field = "config.redis.sentinel_role", then_match = { required = true, one_of = { "master", "slave" }, }
        } },
        { conditional = {
            if_field = "config.strategy", if_match = { eq = "redis-sentinel" },
            then_field = "config.redis.sentinel_addresses", then_match = { required = true },
        } },

        { custom_entity_check = {
            field_sources = { "config" },
            fn = function(entity)
                local config = entity.config
                --???????????????????????????
                if config.strategy == "redis-sentinel" then
                    local ok, err = check_redis_sentinel_addresses(config.redis.sentinel_addresses)
                    if not ok then
                        return nil, err
                    end
                end

                local ok, err = check_has_define_shared_dict(config.counter_dict)
                if not ok then
                    return nil, err
                end
                return true
            end
        } },
    },
}
