local Tauri = require("tauri")

-- Discover Resources directory if packaged in macOS App bundle
pcall(function()
    local ffi = require("ffi")
    if ffi.os == "OSX" then
        ffi.cdef[[ int _NSGetExecutablePath(char* buf, uint32_t* bufsize); ]]
        local buf = ffi.new("char[1024]")
        local size = ffi.new("uint32_t[1]", 1024)
        if ffi.C._NSGetExecutablePath(buf, size) == 0 then
            local full = ffi.string(buf)
            local macos_dir = full:match("^(.*)/Contents/MacOS/")
            if macos_dir then
                local res_dir = macos_dir .. "/Contents/Resources"
                package.path = res_dir .. "/?.lua;" .. res_dir .. "/src-tauri/src/?.lua;" .. res_dir .. "/src/?.lua;" .. package.path
            end
        end
    end
end)

-- 1. Initialize application with configuration
local conf = {}
if __EMBEDDED_CONFIG_JSON__ and __EMBEDDED_CONFIG_JSON__ ~= "" then
    conf = Tauri.json.decode(__EMBEDDED_CONFIG_JSON__) or {}
end
if not conf.productName and not (conf.package and conf.package.name) then
    local conf_raw = io.open("src-tauri/tauri.conf.json", "r") or io.open("tauri.conf.json", "r")
    if conf_raw then
        local text = conf_raw:read("*a")
        conf_raw:close()
        local ok, parsed = pcall(Tauri.json.decode, text)
        if ok and type(parsed) == "table" then
            conf = parsed
        end
    end
end
local app = Tauri.init(conf)

-- Load flight recorder module
package.path = (conf.app and conf.app.srcDir or "src") .. "/?.lua;" .. package.path
local ok_rec, recorder = pcall(require, "flight_recorder")
if not ok_rec then
    package.path = "src-tauri/src/?.lua;" .. package.path
    local ok2, rec2 = pcall(require, "flight_recorder")
    if ok2 then
        recorder = rec2
    else
        error("Failed to load flight_recorder module: " .. tostring(rec2) .. " | package.path=" .. tostring(package.path))
    end
end

-- 2. Register IPC: flight:get_summary
app:register("flight:get_summary", function(payload)
    local req_id = payload and (payload.session_id or payload.session_uuid)
    if req_id and req_id ~= "" then
        recorder.set_current_session_id(req_id)
    end
    local cur_id = recorder.get_current_session_id()
    local summary = recorder.read_transcript_summary(app.json.decode)
    local radar = recorder.get_workspace_radar()
    local vitals = recorder.get_system_vitals()
    local reports = recorder.list_reports()
    local sessions = recorder.list_sessions(app.json.decode)

    return {
        summary = summary,
        radar = radar,
        vitals = vitals,
        reports = reports,
        sessions = sessions,
        current_session_id = cur_id,
        selected_session = cur_id
    }
end)

-- Register IPC: flight:list_sessions
app:register("flight:list_sessions", function(payload)
    return {
        sessions = recorder.list_sessions(app.json.decode),
        current_session_id = recorder.get_current_session_id(),
        selected_session = recorder.get_current_session_id()
    }
end)

-- Register IPC: flight:switch_session
app:register("flight:switch_session", function(payload)
    local target_uuid = payload and (payload.session_id or payload.session_uuid or payload.uuid)
    if target_uuid and target_uuid ~= "" then
        recorder.set_current_session_id(target_uuid)
    end
    local cur_id = recorder.get_current_session_id()
    local summary = recorder.read_transcript_summary(app.json.decode, true)
    local sessions = recorder.list_sessions(app.json.decode)

    return {
        status = "ok",
        current_session_id = cur_id,
        selected_session = cur_id,
        summary = summary,
        sessions = sessions
    }
end)

-- 3. Register lightweight non-blocking polling IPC: flight:poll_updates
app:register("flight:poll_updates", function(payload)
    local last_step = tonumber(payload and payload.last_step) or 0
    local cur_id = recorder.get_current_session_id()
    local cur_summary = recorder.read_transcript_summary(app.json.decode, false, cur_id)
    local cur_step = cur_summary and cur_summary.total_steps or 0
    local has_new = (cur_step > last_step)
    local reports = recorder.list_reports()

    return {
        has_new_events = has_new,
        current_session_id = cur_id,
        total_steps = cur_step,
        summary = has_new and cur_summary or nil,
        radar = (payload and payload.include_radar) and recorder.get_workspace_radar() or nil,
        vitals = recorder.get_system_vitals(),
        reports = reports
    }
end)

-- 4. Register IPC: flight:get_turn
app:register("flight:get_turn", function(payload)
    local turn_id = payload and (payload.turn_id or payload.turnId)
    return recorder.get_turn_events(turn_id, app.json.decode)
end)

-- 5. Register IPC: flight:audit_workspace
app:register("flight:audit_workspace", function(payload)
    return {
        radar = recorder.get_workspace_radar(),
        vitals = recorder.get_system_vitals(),
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
end)

-- 6. Register IPC: flight:export_report
app:register("flight:export_report", function(payload)
    local turn_id = payload and (payload.turn_id or payload.turnId)
    local res = recorder.export_report(app.json.decode, turn_id)
    local reports = recorder.list_reports()
    return {
        export = res,
        reports = reports
    }
end)

-- 7. Register IPC: flight:list_reports
app:register("flight:list_reports", function(payload)
    return {
        reports = recorder.list_reports()
    }
end)

-- 8. Register IPC: flight:read_report
app:register("flight:read_report", function(payload)
    local filename = payload and payload.filename
    return recorder.read_report(filename)
end)

-- 9. Register IPC: flight:reveal_report
app:register("flight:reveal_report", function(payload)
    local filename = payload and payload.filename
    return recorder.reveal_report(filename)
end)

-- 10. Register IPC: flight:trigger_action
app:register("flight:trigger_action", function(payload)
    local action = payload and payload.action or "ping"

    if action == "debug_log" then
        local f = io.open("/tmp/tauri_frontend_debug.log", "a")
        if f then
            f:write(os.date("%H:%M:%S") .. " [FRONTEND] " .. tostring(payload.msg) .. "\n")
            f:close()
        end
        return { status = "ok" }
    elseif action == "ping" then
        return {
            status = "ok",
            message = "Session inspector engine responding at " .. os.date("%H:%M:%S"),
            vitals = recorder.get_system_vitals()
        }
    elseif action == "git_refresh" then
        return {
            status = "ok",
            radar = recorder.get_workspace_radar()
        }
    elseif action == "compact_mem" then
        collectgarbage("collect")
        return {
            status = "ok",
            message = "Garbage collection executed cleanly.",
            vitals = recorder.get_system_vitals()
        }
    end

    return { status = "unknown_action", action = action }
end)

-- 11. Legacy flight:start_stream handler (non-blocking fallback)
app:register("flight:start_stream", function(payload, caller, channel)
    local ch = channel or (payload and payload.onEvent)
    if ch then
        local initial_summary = recorder.read_transcript_summary(app.json.decode)
        ch:send({
            type = "init",
            summary = initial_summary,
            radar = recorder.get_workspace_radar(),
            vitals = recorder.get_system_vitals(),
            reports = recorder.list_reports()
        })
    end
    return { status = "completed", mode = "polling_recommended" }
end)

-- 12. Launch main window
app:create_main_window()
