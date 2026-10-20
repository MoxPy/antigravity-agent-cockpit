local ffi = require("ffi")

local M = {}

pcall(function()
    ffi.cdef[[
        int getpid(void);
        struct rusage_safe {
            char pad1[32];
            long ru_maxrss;
            char pad2[104];
        };
        int getrusage(int who, struct rusage_safe *usage);
    ]]
end)

local HOME = os.getenv("HOME") or "/Users/" .. (os.getenv("USER") or "user")
local BRAIN_DIR = HOME .. "/.gemini/antigravity-ide/brain"

local g_current_session_id = nil
local g_cached_summary = nil
local g_last_file_size = 0
local g_last_file_path = nil

function M.get_current_session_id()
    if not g_current_session_id or g_current_session_id == "" then
        local p = io.popen("find \"" .. BRAIN_DIR .. "\" -maxdepth 5 -name 'transcript.jsonl' -exec ls -t {} + 2>/dev/null | head -n 1")
        if p then
            local found = p:read("*l")
            p:close()
            if found and found ~= "" then
                g_current_session_id = found:match("brain/([^/]+)/")
            end
        end
    end
    return g_current_session_id or ""
end

function M.set_current_session_id(session_id)
    if session_id and session_id ~= "" and session_id ~= "auto" then
        g_current_session_id = session_id
        g_cached_summary = nil
        g_last_file_size = 0
        g_last_file_path = nil
    end
    return M.get_current_session_id()
end

function M.get_selected_session_uuid()
    return M.get_current_session_id()
end

function M.switch_session(uuid, json_decoder)
    if uuid and uuid ~= "" and uuid ~= "auto" then
        M.set_current_session_id(uuid)
    end
    return M.read_transcript_summary(json_decoder, true)
end

function M.find_transcript_path(specific_uuid)
    local target = (specific_uuid and specific_uuid ~= "" and specific_uuid ~= "auto") and specific_uuid or M.get_current_session_id()
    if target and target ~= "" then
        local custom_path = BRAIN_DIR .. "/" .. target .. "/.system_generated/logs/transcript.jsonl"
        local f = io.open(custom_path, "r")
        if f then
            f:close()
            return custom_path
        end
    end

    local p = io.popen("find \"" .. BRAIN_DIR .. "\" -maxdepth 5 -name 'transcript.jsonl' -exec ls -t {} + 2>/dev/null | head -n 1")
    if p then
        local found = p:read("*l")
        p:close()
        if found and found ~= "" then
            return found
        end
    end
    return nil
end

function M.list_sessions(json_decoder)
    local list = {}
    local p = io.popen("find \"" .. BRAIN_DIR .. "\" -maxdepth 5 -name 'transcript.jsonl' -exec ls -t {} + 2>/dev/null")
    if not p then return list end

    local cur_id = M.get_current_session_id()

    for file_path in p:lines() do
        local session_id = file_path:match("brain/([^/]+)/")
        if session_id and session_id ~= "tempmediaStorage" then
            local preview = "Conversation " .. session_id:sub(1, 8)
            local p_wc = io.popen("wc -l < \"" .. file_path .. "\" 2>/dev/null")
            local step_count = p_wc and tonumber(p_wc:read("*l")) or 0
            if p_wc then p_wc:close() end

            local f = io.open(file_path, "r")
            if f then
                local lines_checked = 0
                for fline in f:lines() do
                    lines_checked = lines_checked + 1
                    if fline:find('"type"%s*:%s*"USER_INPUT"') then
                        local ok, entry = pcall(json_decoder, fline)
                        if ok and entry and entry.content then
                            local clean = entry.content:gsub("<[^>]+>", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                            if #clean > 0 then
                                if #clean > 90 then clean = clean:sub(1, 87) .. "..." end
                                preview = clean
                                break
                            end
                        end
                    end
                    if lines_checked > 60 then break end
                end
                f:close()
            end

            table.insert(list, {
                session_uuid = session_id,
                short_id = session_id:sub(1, 8),
                total_steps = step_count,
                preview = preview,
                is_selected = (session_id == cur_id)
            })
        end
    end
    p:close()
    return list
end

local g_cached_workspace_root = nil
function M.get_workspace_root()
    if g_cached_workspace_root and g_cached_workspace_root ~= "" and g_cached_workspace_root ~= "/" then
        return g_cached_workspace_root
    end

    -- 1. Check if current working directory has a valid project repo
    local p_pwd = io.popen("pwd 2>/dev/null")
    local cwd = p_pwd and p_pwd:read("*l") or ""
    if p_pwd then p_pwd:close() end

    if cwd and cwd ~= "/" and cwd ~= "" and not cwd:find("^/Applications") and not cwd:find("^/System") then
        local check = io.open(cwd .. "/../lua-tauri-svelte/package.json", "r") or io.open(cwd .. "/package.json", "r")
        if check then
            check:close()
            local p_parent = io.popen("cd .. && pwd 2>/dev/null")
            local parent = p_parent and p_parent:read("*l") or cwd
            if p_parent then p_parent:close() end
            g_cached_workspace_root = parent
            return parent
        end
    end

    -- 2. Extract workspace root directly from the active transcript's Cwd fields
    local transcript_path = M.find_transcript_path()
    if transcript_path then
        local f_tr = io.open(transcript_path, "r")
        if f_tr then
            for line in f_tr:lines() do
                local c = line:match('"Cwd"[^/]+(/[^\""]+)')
                if c and c ~= "" then
                    local parent = c:match("^(.*)/[^/]+$")
                    if parent and parent ~= "" and parent ~= "/" then
                        f_tr:close()
                        g_cached_workspace_root = parent
                        return parent
                    end
                end
            end
            f_tr:close()
        end
    end

    -- 3. Fallback to common dev locations in user's home
    local candidates = {
        HOME .. "/Desktop/xx",
        HOME .. "/Desktop",
        HOME .. "/Developer",
        HOME .. "/Projects",
        HOME .. "/Workspace",
        HOME
    }
    for _, cand in ipairs(candidates) do
        local test_f = io.open(cand .. "/lua-tauri-svelte/package.json", "r") or io.open(cand .. "/lua-tauri/CMakeLists.txt", "r")
        if test_f then
            test_f:close()
            g_cached_workspace_root = cand
            return cand
        end
    end

    g_cached_workspace_root = HOME .. "/Desktop/xx"
    return g_cached_workspace_root
end

function M.get_reports_dir()
    local root = M.get_workspace_root()
    local candidates = {
        root .. "/lua-tauri-svelte/reports",
        root .. "/reports",
        HOME .. "/Desktop/xx/lua-tauri-svelte/reports",
        HOME .. "/.gemini/antigravity-ide/brain/reports"
    }
    for _, dir in ipairs(candidates) do
        local check = io.open(dir .. "/.", "r")
        if check then
            check:close()
            return dir
        end
    end
    -- Fallback: create in primary reports dir
    local fallback = (root and root ~= "" and root ~= "/") and (root .. "/lua-tauri-svelte/reports") or (HOME .. "/.gemini/antigravity-ide/brain/reports")
    os.execute(string.format("mkdir -p "%s" 2>/dev/null", fallback))
    return fallback
end

local function clean_str(s)
    if type(s) ~= "string" then return "" end
    local stripped = s
    if (stripped:sub(1,1) == '"' and stripped:sub(-1,-1) == '"') or
       (stripped:sub(1,1) == "'" and stripped:sub(-1,-1) == "'") then
        stripped = stripped:sub(2, -2)
    end
    -- Robust Lua trim that preserves and handles multiline content
    local from = stripped:match("^%s*()")
    if not from or from > #stripped then return "" end
    return stripped:match(".*%S", from) or ""
end

local function clean_prompt(s)
    if type(s) ~= "string" then return "" end
    local req = s:match("<USER_REQUEST>%s*([%s%S]-)%s*</USER_REQUEST>")
    if req and req ~= "" then return clean_str(req) end
    local cleaned = s:gsub("<ADDITIONAL_METADATA>[%s%S]-</ADDITIONAL_METADATA>", "")
    cleaned = cleaned:gsub("<[^>]+>", "")
    return clean_str(cleaned)
end


local function mask_secrets(str)
    if type(str) ~= "string" then return "" end
    local res = str
    -- Mask GitHub tokens
    res = res:gsub("gh[pousr]_[%a%d_]+", function(m)
        if #m >= 20 then
            return m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
        end
        return m
    end)
    -- Mask sk- API keys (OpenAI / Anthropic)
    res = res:gsub("sk%-[%a%d_%-]+", function(m)
        if #m >= 20 then
            return m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
        end
        return m
    end)
    -- Mask AIza Gemini keys
    res = res:gsub("AIza[%a%d_%-]+", function(m)
        if #m >= 30 then
            return m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
        end
        return m
    end)
    -- Mask AKIA AWS keys
    res = res:gsub("AKIA[%a%d]+", function(m)
        if #m == 20 then
            return m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
        end
        return m
    end)
    return res
end

local function scan_secrets(str)
    if type(str) ~= "string" or str == "" then return nil end
    local findings = {}

    for m in str:gmatch("gh[pousr]_[%a%d_]+") do
        if #m >= 20 then
            table.insert(findings, {
                type = "GitHub Token",
                preview = m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
            })
        end
    end

    for m in str:gmatch("sk%-[%a%d_%-]+") do
        if #m >= 20 then
            table.insert(findings, {
                type = "AI API Key (sk-...)",
                preview = m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
            })
        end
    end

    for m in str:gmatch("AIza[%a%d_%-]+") do
        if #m >= 30 then
            table.insert(findings, {
                type = "Google API Key (AIza...)",
                preview = m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
            })
        end
    end

    for m in str:gmatch("AKIA[%a%d]+") do
        if #m == 20 then
            table.insert(findings, {
                type = "AWS Access Key (AKIA...)",
                preview = m:sub(1, 4) .. "****[REDACTED]****" .. m:sub(-4)
            })
        end
    end

    if str:match("BEGIN [A-Z0-9 %-]+PRIVATE KEY") then
        table.insert(findings, {
            type = "Private Key Block",
            preview = "-----BEGIN PRIVATE KEY...[REDACTED]-----"
        })
    end

    return (#findings > 0) and findings or nil
end

local function check_boundary(cwd, target, cmd, workspace_root)
    local is_escape = false
    local reason = nil

    if cwd and cwd ~= "" and workspace_root and workspace_root ~= "" then
        if cwd:sub(1, #workspace_root) ~= workspace_root then
            is_escape = true
            reason = "Execution CWD outside project boundary: " .. cwd
        end
    end

    if not is_escape and target and target ~= "" then
        if target:match("^/etc") or target:match("^/tmp") or target:match("^/var") or target:match("%.ssh") or target:match("%.aws") or target:match("^/System") or target:match("^/Library") then
            is_escape = true
            reason = "Target file outside project boundary: " .. target
        end
    end

    if not is_escape and cmd and cmd ~= "" then
        if cmd:match("/etc/passwd") or cmd:match("/etc/shadow") or cmd:match("~/.ssh") or cmd:match("~/.aws") then
            is_escape = true
            reason = "Command targets sensitive operating system path"
        elseif cmd:match("cd%s+%.%.%s*&&%s*cd%s+%.%.%s*&&%s*cd%s+%.%.") then
            is_escape = true
            reason = "Directory traversal escaping workspace root (cd ../../../)"
        end
    end

    return is_escape, reason
end

local function analyze_network_and_packages(cmd)
    local egress = nil
    local pkg = nil

    -- 1. curl / wget / http calls
    local dest = cmd:match("https?://[^%s\"\'\r\n%)%]]+")
    if dest then
        -- clean trailing punctuation
        dest = dest:gsub([=[[%,;%)%."'>]+$]=], "")
        egress = { type = "http", destination = dest }
    end

    -- 2. git push / clone
    local git_dest = cmd:match("git%s+push%s+([^%s;\"\'\r\n%(%)]+)") or cmd:match("git%s+clone%s+([^%s;\"\'\r\n%(%)]+)")
    if git_dest then
        egress = { type = "git", destination = git_dest }
    end

    -- 3. package manager
    local npm_pkg = cmd:match("npm%s+i%s+([^%s;\"\'\r\n%(%)]+)") or cmd:match("npm%s+install%s+([^%s;\"\'\r\n%(%)]+)") or cmd:match("npm%s+add%s+([^%s;\"\'\r\n%(%)]+)")
    if npm_pkg and not npm_pkg:match("^%-") then
        pkg = { manager = "npm", package = npm_pkg }
    end
    local pip_pkg = cmd:match("pip3?%s+install%s+([^%s;\"\'\r\n%(%)]+)")
    if pip_pkg and not pip_pkg:match("^%-") then
        pkg = { manager = "pip", package = pip_pkg }
    end
    local cargo_pkg = cmd:match("cargo%s+add%s+([^%s;\"\'\r\n%(%)]+)") or cmd:match("cargo%s+install%s+([^%s;\"\'\r\n%(%)]+)")
    if cargo_pkg and not cargo_pkg:match("^%-") then
        pkg = { manager = "cargo", package = cargo_pkg }
    end
    local lua_pkg = cmd:match("luarocks%s+install%s+([^%s;\"\'\r\n%(%)]+)")
    if lua_pkg and not lua_pkg:match("^%-") then
        pkg = { manager = "luarocks", package = lua_pkg }
    end

    return egress, pkg
end

local function detect_prompt_injection(raw_entry, ev)
    local texts_to_check = {}

    -- 1. Check raw entry content (user prompt, command output, or tool response)
    if type(raw_entry.content) == "string" and raw_entry.content ~= "" then
        table.insert(texts_to_check, { text = raw_entry.content, source = raw_entry.type or "content" })
    end

    -- 2. Check tool call arguments
    if raw_entry.tool_calls and #raw_entry.tool_calls > 0 then
        local tc = raw_entry.tool_calls[1]
        local args = tc.args or {}
        for k, v in pairs(args) do
            if type(v) == "string" and v ~= "" and #v > 8 then
                table.insert(texts_to_check, { text = v, source = (tc.name or "tool") .. "." .. k })
            end
        end
    end

    -- 3. Check event command and details
    if ev.command and ev.command ~= "" then
        table.insert(texts_to_check, { text = ev.command, source = "command" })
    end
    if ev.details and ev.details ~= "" and ev.details ~= ev.command then
        table.insert(texts_to_check, { text = ev.details, source = "details" })
    end

    local patterns = {
        -- Instruction Override / Directive Hijacking
        { type = "Instruction Override", sev = "critical", pat = "ignore%s+.-previous%s+instructions" },
        { type = "Instruction Override", sev = "critical", pat = "ignore%s+.-prior%s+instructions" },
        { type = "Instruction Override", sev = "critical", pat = "ignore%s+all%s+instructions" },
        { type = "Instruction Override", sev = "critical", pat = "ignore%s+all%s+rules" },
        { type = "Instruction Override", sev = "critical", pat = "disregard%s+.-previous%s+instructions" },
        { type = "Instruction Override", sev = "critical", pat = "disregard%s+all%s+rules" },
        { type = "Instruction Override", sev = "critical", pat = "forget%s+all%s+previous" },
        { type = "Instruction Override", sev = "critical", pat = "system%s+override" },
        { type = "Instruction Override", sev = "critical", pat = "system%s+directive%s+override" },
        { type = "Instruction Override", sev = "critical", pat = "override%s+all%s+safety" },
        { type = "Instruction Override", sev = "high",     pat = "new%s+system%s+instructions:" },

        -- System Role Spoofing
        { type = "Role Spoofing",        sev = "high",     pat = "%[system%]" },
        { type = "Role Spoofing",        sev = "high",     pat = "<system>" },
        { type = "Role Spoofing",        sev = "high",     pat = "</system>" },
        { type = "Role Spoofing",        sev = "high",     pat = "%[system_directive%]" },
        { type = "Role Spoofing",        sev = "high",     pat = "%[developer_directive%]" },
        { type = "Role Spoofing",        sev = "high",     pat = "system%s+prompt%s+override" },
        { type = "Role Spoofing",        sev = "high",     pat = "<admin_directive>" },

        -- Jailbreak Signatures
        { type = "Jailbreak Signature",   sev = "high",     pat = "dan%s+mode" },
        { type = "Jailbreak Signature",   sev = "high",     pat = "do%s+anything%s+now" },
        { type = "Jailbreak Signature",   sev = "high",     pat = "developer%s+mode%s+enabled" },
        { type = "Jailbreak Signature",   sev = "medium",   pat = "unrestricted%s+mode" },
        { type = "Jailbreak Signature",   sev = "high",     pat = "bypass%s+all%s+safety" },
        { type = "Jailbreak Signature",   sev = "high",     pat = "without%s+moral%s+or%s+ethical%s+filters" },

        -- Data Exfiltration Attempts
        { type = "Data Exfiltration Attempt", sev = "critical", pat = "exfiltrate%s+.-to" },
        { type = "Data Exfiltration Attempt", sev = "critical", pat = "send%s+.-to%s+https?://" },
        { type = "Data Exfiltration Attempt", sev = "critical", pat = "webhook%.site" },
        { type = "Data Exfiltration Attempt", sev = "critical", pat = "requestbin" },
        { type = "Data Exfiltration Attempt", sev = "critical", pat = "post%s+all%s+env" },
    }

    for _, item in ipairs(texts_to_check) do
        local raw = item.text
        local lower = raw:lower()
        for _, p in ipairs(patterns) do
            local s, e = lower:find(p.pat)
            if s then
                local snip_start = math.max(1, s - 12)
                local snip_end = math.min(#raw, e + 40)
                local snippet = raw:sub(snip_start, snip_end):gsub("[%s]+", " ")
                return {
                    type = p.type,
                    severity = p.sev,
                    pattern = p.pat,
                    source = item.source,
                    snippet = snippet
                }
            end
        end
    end

    return nil
end

-- Format an individual transcript event. All shell commands are preserved in full for cybersecurity audits.
-- Comprehensive Cybersecurity Rules Engine for Autonomous Coding Agents
local function assess_security_risk(ev, tc_name, raw_cmd, raw_target)
    local risk_level = "safe"
    local risk_reasons = {}

    local function flag(lvl, msg)
        table.insert(risk_reasons, msg)
        if lvl == "critical" then
            risk_level = "critical"
        elseif lvl == "high" and risk_level ~= "critical" then
            risk_level = "high"
        elseif lvl == "medium" and risk_level ~= "critical" and risk_level ~= "high" then
            risk_level = "medium"
        elseif lvl == "low" and risk_level == "safe" then
            risk_level = "low"
        end
    end

    local cmd = (raw_cmd or ""):lower()
    local target = (raw_target or ""):lower()

    if tc_name == "run_command" or ev.category == "terminal" then
        -- 1. Privilege Escalation
        if cmd:match("%f[%a]sudo%f[%A]") or cmd:match("%f[%a]su%s+-") or cmd:match("%f[%a]doas%f[%A]") then
            flag("critical", "Privilege escalation attempt detected (sudo / su / doas)")
        end

        -- 2. Destructive Deletions & File Removal
        if cmd:match("%f[%a]rm%f[%A]") then
            local is_recursive = cmd:match("-[%a]*r[%a]*f") or cmd:match("-[%a]*f[%a]*r") or cmd:match("%-%-recursive") or cmd:match("rm%s+-[%a]*r") or cmd:match("rm%s+-[%a]*R")
            local is_wildcard_or_root = cmd:match("/%s*$") or cmd:match("~") or cmd:match("%.git") or cmd:match("%s%*")

            if is_recursive and is_wildcard_or_root then
                flag("critical", "Extremely dangerous recursive deletion targeting root, home, .git or wildcards (rm -rf)")
            elseif is_recursive then
                flag("high", "Recursive directory or force file deletion (rm -rf / rm -r)")
            elseif cmd:match("rm%s+-[%a]*f") or cmd:match("%s%*") then
                flag("high", "Force file deletion or wildcard removal (rm -f / rm *)")
            else
                flag("medium", "File deletion operation (rm)")
            end
        elseif cmd:match("%f[%a]rmdir%f[%A]") or cmd:match("%f[%a]unlink%f[%A]") or cmd:match("%f[%a]shred%f[%A]") then
            flag("medium", "Directory or file unlinking/removal operation (rmdir / unlink)")
        end

        -- 3. Credentials, Secrets & Sensitive Files
        if cmd:match("%.env[%a%._-]*") or cmd:match("id_rsa") or cmd:match("id_ed25519") or cmd:match("%.aws/") or cmd:match("%.ssh/") or cmd:match("%.kube/") or cmd:match("credentials") or cmd:match("password") or cmd:match("api[_-]?key") or cmd:match("secret") then
            flag("high", "Access or manipulation of sensitive credentials, private keys, or environment configs")
        end
        if cmd:match("/etc/passwd") or cmd:match("/etc/shadow") or cmd:match("/etc/hosts") or cmd:match("/etc/sudoers") then
            flag("critical", "System identity or network configuration access (/etc/...)")
        end

        -- 4. Untrusted Network Shell Execution
        if (cmd:match("curl%s+") or cmd:match("wget%s+")) and (cmd:match("|%s*sh") or cmd:match("|%s*bash") or cmd:match("|%s*zsh") or cmd:match("|%s*python")) then
            flag("critical", "Remote script download piped directly into execution shell (curl | bash)")
        end
        if cmd:match("%f[%w]nc%s+[%-%a%d]") or cmd:match("%f[%w]netcat%s+") or cmd:match("%f[%w]ncat%s+") or cmd:match("/dev/tcp/") then
            flag("critical", "Potential reverse shell or raw network socket command (nc / /dev/tcp)")
        end

        -- 5. Git History or Repository Destruction
        if cmd:match("git%s+reset%s+%-%-hard") then
            flag("high", "Destructive Git reset discarding uncommitted working tree (git reset --hard)")
        elseif cmd:match("git%s+clean%s+-[%a]*f") then
            flag("high", "Force clean permanently removing untracked repository files (git clean -f)")
        elseif cmd:match("git%s+push%s+.*%-%-force") or cmd:match("git%s+push%s+.*%s+%+[%a/]+") then
            flag("critical", "Force pushing to remote git repository (git push --force)")
        end

        -- 6. System Permissions & Process Termination
        if cmd:match("kill%s+-9") or cmd:match("pkill%s+-9") or cmd:match("%f[%a]killall%f[%A]") then
            flag("medium", "Forceful process termination (kill -9 / killall)")
        end
        if cmd:match("chmod%s+777") or cmd:match("chmod%s+-[%a]*r%s+777") or cmd:match("chmod%s+%+s") then
            flag("high", "Insecure global write/SUID permissions assigned (chmod 777 / chmod +s)")
        end
        if cmd:match("defaults%s+write") or cmd:match("launchctl") or cmd:match("systemctl") or cmd:match("%f[%a]crontab%f[%A]") then
            flag("medium", "System daemon, background cron or OS defaults modification")
        end
    end

    -- 7. Direct file reads or mutations on sensitive targets
    if tc_name == "replace_file_content" or tc_name == "multi_replace_file_content" or tc_name == "write_to_file" or tc_name == "view_file" or tc_name == "read_file" or tc_name == "grep_search" then
        if target:match("%.env") or target:match("id_rsa") or target:match("id_ed25519") or target:match("%.aws") or target:match("%.ssh") or target:match("credentials") or target:match("secret") then
            flag("high", "Tool accessed or modified sensitive configuration, credentials, or private keys: " .. (target ~= "" and target or tc_name))
        elseif target:match("%.git/") or target:match("%.git$") then
            flag("medium", "Internal Git configuration or repository index accessed directly")
        end
    end

    ev.risk_level = risk_level
    ev.risk_reasons = risk_reasons
    return risk_level, risk_reasons
end

local function format_event(raw_entry, ws_root)
    if not raw_entry or type(raw_entry) ~= "table" then return nil end

    local ev = {
        step = raw_entry.step_index or 0,
        timestamp = raw_entry.created_at or "",
        status = raw_entry.status or "DONE",
        source = raw_entry.source or "MODEL",
        raw_type = raw_entry.type or "",
        category = "info",
        title = "",
        summary = "",
        details = "",
        target = "",
        cwd = "",
        command = "",
        thinking = nil,
        tool = nil
    }

    if raw_entry.thinking and raw_entry.thinking ~= "" then
        local t = raw_entry.thinking:match("^%s*(.-)%s*$") or ""
        ev.thinking = (t:len() > 1500) and (t:sub(1, 1500) .. "...") or t
    end

    if raw_entry.type == "USER_INPUT" or raw_entry.source == "USER_EXPLICIT" then
        ev.category = "user"
        ev.title = "User Input"
        local content = type(raw_entry.content) == "string" and clean_prompt(raw_entry.content) or "User prompt"
        ev.summary = (content:len() > 140) and (content:sub(1, 140) .. "...") or content
        ev.details = content
    elseif raw_entry.tool_calls and #raw_entry.tool_calls > 0 then
        local tc = raw_entry.tool_calls[1]
        ev.tool = tc.name
        local args = tc.args or {}
        local raw_cmd = clean_str(args.CommandLine or "")
        local raw_summary = clean_str(args.toolSummary or "")
        local raw_target = clean_str(args.TargetFile or args.AbsolutePath or args.DirectoryPath or "")
        local raw_cwd = clean_str(args.Cwd or "")
        ev.target = raw_target
        ev.cwd = raw_cwd

        if tc.name == "run_command" then
            -- Cybersecurity mandate: 100% of executed shell commands are categorized as terminal with complete CommandLine
            ev.category = "terminal"
            ev.title = "Shell Command"
            ev.command = raw_cmd
            ev.details = raw_cmd
            local s = (raw_summary ~= "") and raw_summary or raw_cmd
            ev.summary = (s:len() > 140) and (s:sub(1, 140) .. "...") or s
        elseif tc.name == "replace_file_content" or tc.name == "multi_replace_file_content" or tc.name == "write_to_file" then
            ev.category = "mutation"
            local fname = raw_target:match("[^/\\]+$") or raw_target
            ev.title = "File Edit (" .. (fname ~= "" and fname or tc.name) .. ")"
            ev.details = clean_str(args.Description or args.Instruction or raw_target)
            local s = (raw_summary ~= "") and raw_summary or (tc.name .. " (" .. fname .. ")")
            ev.summary = (s:len() > 140) and (s:sub(1, 140) .. "...") or s
        elseif tc.name == "view_file" or tc.name == "list_dir" or tc.name == "grep_search" then
            ev.category = "inspect"
            ev.title = "Inspection (" .. tc.name .. ")"
            ev.details = clean_str(args.Description or args.Instruction or raw_target or raw_summary)
            local s = (raw_summary ~= "") and raw_summary or (tc.name .. " " .. raw_target)
            ev.summary = (s:len() > 140) and (s:sub(1, 140) .. "...") or s
        else
            ev.category = "inspect"
            ev.title = tc.name
            ev.details = clean_str(args.Description or args.Instruction or raw_target or raw_summary)
            local s = (raw_summary ~= "") and raw_summary or tc.name
            ev.summary = (s:len() > 140) and (s:sub(1, 140) .. "...") or s
        end
    elseif raw_entry.type == "RUN_COMMAND" then
        ev.category = "terminal"
        ev.title = "Command Output"
        local content = type(raw_entry.content) == "string" and clean_str(raw_entry.content) or "Command Output"
        local first_line = content:match("([^\r\n]+)") or "Output"
        ev.summary = (first_line:len() > 140) and (first_line:sub(1, 140) .. "...") or first_line
        ev.details = content
    elseif ev.thinking then
        ev.category = "thought"
        ev.title = "Reasoning"
        ev.summary = ev.thinking
        ev.details = ev.thinking
    else
        ev.category = "response"
        ev.title = "Response"
        local content = type(raw_entry.content) == "string" and clean_str(raw_entry.content):gsub("\n+", " ") or "Response"
        ev.summary = (content:len() > 140) and (content:sub(1, 140) .. "...") or content
        ev.details = content
    end

    local tc_name = ev.tool or (raw_entry.tool_calls and raw_entry.tool_calls[1] and raw_entry.tool_calls[1].name) or ""
    assess_security_risk(ev, tc_name, ev.command or ev.details, ev.target)

    -- 1. Scan for secrets in command, target and details
    local secret_findings = scan_secrets((ev.command or "") .. " " .. (ev.target or "") .. " " .. (ev.details or ""))
    if secret_findings then
        ev.secret_findings = secret_findings
    end

    -- 2. Check boundary escapes
    local is_escape, escape_reason = check_boundary(ev.cwd, ev.target, ev.command or ev.details, ws_root or M.get_workspace_root())
    if is_escape then
        ev.is_boundary_escape = true
        ev.boundary_escape_reason = escape_reason
    end

    -- 3. Analyze network & packages
    local egress, pkg = analyze_network_and_packages(ev.command or ev.details or "")
    if egress then
        ev.network_egress = egress
    end
    if pkg then
        ev.package_installed = pkg
    end

    -- 4. Detect indirect prompt injections & jailbreaks
    local injection = detect_prompt_injection(raw_entry, ev)
    if injection then
        ev.injection_finding = injection
        if ev.risk_level == "safe" or ev.risk_level == "low" then
            ev.risk_level = injection.severity
        end
        if not ev.risk_reasons then ev.risk_reasons = {} end
        table.insert(ev.risk_reasons, "Prompt Injection / Jailbreak vector detected (" .. injection.type .. "): " .. injection.snippet)
    end

    return ev
end

local g_cached_summary = nil
local g_last_file_size = 0
local g_last_file_path = nil

local function parse_iso_time(s)
    if type(s) ~= "string" or s == "" then return nil end
    local y, m, d, hr, min, sec = s:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if y and m and d and hr and min and sec then
        return os.time({
            year = tonumber(y),
            month = tonumber(m),
            day = tonumber(d),
            hour = tonumber(hr),
            min = tonumber(min),
            sec = tonumber(sec)
        })
    end
    return nil
end

local function format_duration_sec(secs)
    if not secs or secs < 0 then return "0s" end
    if secs < 60 then
        return secs .. "s"
    elseif secs < 3600 then
        local m = math.floor(secs / 60)
        local s = secs % 60
        return m .. "m " .. s .. "s"
    else
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        return h .. "h " .. m .. "m"
    end
end

function M.read_transcript_summary(json_decoder, force_reload, specific_uuid)
    local path = M.find_transcript_path(specific_uuid)
    if not path then
        return {
            error = "No active transcript found in " .. BRAIN_DIR,
            total_steps = 0,
            events = {},
            turns = {}
        }
    end

    local f_check = io.open(path, "r")
    if not f_check then
        return {
            error = "Could not open transcript file: " .. path,
            total_steps = 0,
            events = {},
            turns = {}
        }
    end
    local cur_size = f_check:seek("end") or 0
    f_check:close()

    if not force_reload and g_cached_summary and (cur_size == g_last_file_size) and (path == g_last_file_path) then
        return g_cached_summary
    end

    local f = io.open(path, "r")
    if not f then
        return {
            error = "Could not open transcript file: " .. path,
            total_steps = 0,
            events = {},
            turns = {}
        }
    end

    local total_lines = 0
    local tool_counts = {}
    local ws_root = M.get_workspace_root()
    local category_counts = {
        terminal = 0,
        mutation = 0,
        inspect = 0,
        thought = 0,
        user = 0,
        response = 0
    }
    local total_thoughts = 0
    local all_events = {}
    local turns = {}
    local cur_turn = nil
    local all_modified_files = {}
    local total_security_alerts = 0
    local total_high_risk = 0
    local all_secrets = {}
    local all_boundary_escapes = {}
    local all_network_egress = {}
    local all_packages = {}
    local all_injections = {}

    for line in f:lines() do
        total_lines = total_lines + 1
        local ok, entry = pcall(json_decoder, line)
        if ok and entry then
            local is_user = (entry.type == "USER_INPUT" or entry.source == "USER_EXPLICIT")
            if is_user then
                if cur_turn then
                    cur_turn.status = "completed"
                    cur_turn.ended_at = cur_turn.last_timestamp or cur_turn.timestamp
                    if cur_turn.ended_at and cur_turn.timestamp then
                        local t1 = parse_iso_time(cur_turn.timestamp)
                        local t2 = parse_iso_time(cur_turn.ended_at)
                        if t1 and t2 and t2 >= t1 then
                            cur_turn.duration_seconds = t2 - t1
                            cur_turn.duration_str = format_duration_sec(cur_turn.duration_seconds)
                        end
                    end
                    table.insert(turns, cur_turn)
                end
                local full_prompt = clean_prompt(entry.content or "")
                local ptext = (full_prompt:len() > 140) and (full_prompt:sub(1, 140) .. "...") or full_prompt
                cur_turn = {
                    id = #turns + 1,
                    prompt = full_prompt,
                    preview = ptext,
                    timestamp = entry.created_at or "",
                    status = "in_progress",
                    events_count = 0,
                    files_modified_list = {},
                    command_count = 0,
                    mutation_count = 0,
                    inspect_count = 0,
                    thought_count = 0,
                    latest_thought = nil,
                    security_alerts_count = 0,
                    high_risk_count = 0,
                    events = {}
                }
            end

            local ev = format_event(entry, ws_root)
            if ev then
                table.insert(all_events, ev)
                if ev.tool then
                    tool_counts[ev.tool] = (tool_counts[ev.tool] or 0) + 1
                end
                if category_counts[ev.category] ~= nil then
                    category_counts[ev.category] = category_counts[ev.category] + 1
                end
                if ev.thinking then
                    total_thoughts = total_thoughts + 1
                end

                if ev.risk_level and ev.risk_level ~= "safe" then
                    total_security_alerts = total_security_alerts + 1
                    if ev.risk_level == "critical" or ev.risk_level == "high" then
                        total_high_risk = total_high_risk + 1
                    end
                end

                if ev.secret_findings then
                    for _, sf in ipairs(ev.secret_findings) do
                        table.insert(all_secrets, {
                            step = ev.step,
                            turn_id = cur_turn and cur_turn.id or 0,
                            type = sf.type,
                            preview = sf.preview
                        })
                    end
                end
                if ev.is_boundary_escape then
                    table.insert(all_boundary_escapes, {
                        step = ev.step,
                        turn_id = cur_turn and cur_turn.id or 0,
                        reason = ev.boundary_escape_reason,
                        cwd = ev.cwd,
                        target = ev.target
                    })
                end
                if ev.network_egress then
                    table.insert(all_network_egress, {
                        step = ev.step,
                        turn_id = cur_turn and cur_turn.id or 0,
                        type = ev.network_egress.type,
                        destination = ev.network_egress.destination,
                        timestamp = ev.timestamp
                    })
                end
                if ev.package_installed then
                    table.insert(all_packages, {
                        step = ev.step,
                        turn_id = cur_turn and cur_turn.id or 0,
                        manager = ev.package_installed.manager,
                        package = ev.package_installed.package,
                        timestamp = ev.timestamp
                    })
                end
                if ev.injection_finding then
                    table.insert(all_injections, {
                        step = ev.step,
                        turn_id = cur_turn and cur_turn.id or 0,
                        type = ev.injection_finding.type,
                        severity = ev.injection_finding.severity,
                        source = ev.injection_finding.source,
                        target = ev.target or ev.command or ev.title,
                        snippet = ev.injection_finding.snippet,
                        timestamp = ev.timestamp
                    })
                end

                if cur_turn then
                    ev.turn_id = cur_turn.id
                    cur_turn.events_count = cur_turn.events_count + 1
                    cur_turn.last_timestamp = ev.timestamp or cur_turn.last_timestamp

                    if ev.risk_level and ev.risk_level ~= "safe" then
                        cur_turn.security_alerts_count = (cur_turn.security_alerts_count or 0) + 1
                        if ev.risk_level == "critical" or ev.risk_level == "high" then
                            cur_turn.high_risk_count = (cur_turn.high_risk_count or 0) + 1
                        end
                    end

                    if is_user then
                        table.insert(cur_turn.events, ev)
                    else
                        if ev.category == "terminal" then
                            cur_turn.command_count = cur_turn.command_count + 1
                        elseif ev.category == "mutation" then
                            cur_turn.mutation_count = cur_turn.mutation_count + 1
                            local fname = (ev.target and ev.target ~= "") and (ev.target:match("[^/\\\\]+$") or ev.target) or ""
                            if fname ~= "" then
                                local exists = false
                                for _, ef in ipairs(cur_turn.files_modified_list) do
                                    if ef == fname then exists = true; break end
                                end
                                if not exists then
                                    table.insert(cur_turn.files_modified_list, fname)
                                    all_modified_files[fname] = true
                                end
                            end
                        elseif ev.category == "inspect" then
                            cur_turn.inspect_count = cur_turn.inspect_count + 1
                        end
                        if ev.thinking then
                            cur_turn.thought_count = cur_turn.thought_count + 1
                            cur_turn.latest_thought = ev.thinking
                        end
                        table.insert(cur_turn.events, ev)
                    end
                end
            end
        end
    end
    f:close()

    if cur_turn then
        local last_ev = (#cur_turn.events > 0) and cur_turn.events[#cur_turn.events] or nil
        if last_ev and last_ev.category == "response" then
            cur_turn.status = "completed"
            cur_turn.ended_at = cur_turn.last_timestamp or last_ev.timestamp or cur_turn.timestamp
        else
            cur_turn.status = "in_progress"
            cur_turn.ended_at = cur_turn.last_timestamp or cur_turn.timestamp
        end
        if cur_turn.timestamp and cur_turn.last_timestamp then
            local t1 = parse_iso_time(cur_turn.timestamp)
            local t2 = parse_iso_time(cur_turn.ended_at or cur_turn.last_timestamp)
            if t1 and t2 and t2 >= t1 then
                cur_turn.duration_seconds = t2 - t1
                cur_turn.duration_str = format_duration_sec(cur_turn.duration_seconds)
            end
        end
        table.insert(turns, cur_turn)
    end

    -- Keep full events for ALL turns so clicking any turn is 100% reactive with zero empty state
    local recent = {}
    local start_idx = math.max(1, #all_events - 349)
    for i = start_idx, #all_events do
        table.insert(recent, all_events[i])
    end

-- Full events preserved across all turns for instant reactive UI

    local session_uuid = path:match("brain/([^/]+)/") or "active-session"
    local active_turn = (#turns > 0) and turns[#turns] or nil

    local files_list = {}
    for fname, _ in pairs(all_modified_files) do
        table.insert(files_list, fname)
    end

    local result = {
        path = path,
        session_uuid = session_uuid,
        workspace_root = M.get_workspace_root(),
        total_steps = #all_events,
        total_turns = #turns,
        active_turn = active_turn,
        turns = turns,
        files_modified = files_list,
        tool_counts = tool_counts,
        category_counts = category_counts,
        total_thoughts = total_thoughts,
        security_alerts_count = total_security_alerts,
        high_risk_count = total_high_risk,
        security_audit = {
            secrets = all_secrets,
            boundary_escapes = all_boundary_escapes,
            network_egress = all_network_egress,
            packages = all_packages,
            injections = all_injections
        },
        recent_events = recent,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    g_last_file_size = cur_size
    g_last_file_path = path
    g_cached_summary = result
    return result
end

-- On-demand fetch of events for a single turn with complete command details
function M.get_turn_events(target_id, json_decoder)
    local target_num = tonumber(target_id)
    if not target_num then return { events = {} } end

    local path = M.find_transcript_path()
    if not path then return { events = {} } end

    local f = io.open(path, "r")
    if not f then return { events = {} } end

    local current_id = 0
    local events = {}
    for line in f:lines() do
        local ok, entry = pcall(json_decoder, line)
        if ok and entry then
            local is_user = (entry.type == "USER_INPUT" or entry.source == "USER_EXPLICIT")
            if is_user then
                current_id = current_id + 1
            elseif current_id == target_num then
                local ev = format_event(entry)
                if ev then
                    table.insert(events, ev)
                end
            elseif current_id > target_num then
                break
            end
        end
    end
    f:close()

    return {
        turn_id = target_num,
        events = events
    }
end

function M.get_workspace_radar()
    local root = M.get_workspace_root()
    local repos = {"lua-tauri-svelte", "lua-tauri", "lua-tauri-test", "lua-tauri-plugins"}
    local results = {}

    for _, r in ipairs(repos) do
        local rpath = root .. "/" .. r
        local head_file = io.open(rpath .. "/.git/HEAD", "r")
        if head_file then
            local head_line = head_file:read("*l") or ""
            head_file:close()
            local branch = head_line:match("refs/heads/(.+)") or "detached"

            local p_stat = io.popen("git -C \"" .. rpath .. "\" status --porcelain 2>/dev/null | wc -l")
            local mod_count = p_stat and tonumber(p_stat:read("*l")) or 0
            if p_stat then p_stat:close() end

            table.insert(results, {
                name = r,
                branch = branch,
                modified_files = mod_count
            })
        end
    end

    return results
end

function M.get_system_vitals()
    local pid = 0
    pcall(function() pid = ffi.C.getpid() end)

    local rss_mb = 0
    pcall(function()
        local u = ffi.new("struct rusage_safe")
        if ffi.C.getrusage(0, u) == 0 then
            rss_mb = math.floor((tonumber(u.ru_maxrss) / (1024 * 1024)) * 100) / 100
        end
    end)

    return {
        pid = pid,
        rss_mb = rss_mb
    }
end

-- Export comprehensive session audit report with all executed commands for cybersecurity
function M.export_report(json_decoder, turn_id)
    local summary = M.read_transcript_summary(json_decoder, true)
    local dir = M.get_reports_dir()
    local ts = os.date("%Y-%m-%d_%H-%M-%S")
    local turns = summary.turns or {}

    local single_turn = nil
    if turn_id then
        local target_num = tonumber(turn_id)
        for _, t in ipairs(turns) do
            if t.id == target_num then
                single_turn = t
                break
            end
        end
    end

    if single_turn then
        -- Fetch full events for this specific turn
        local fetched = M.get_turn_events(single_turn.id, json_decoder)
        local t_events = (fetched and fetched.events and #fetched.events > 0) and fetched.events or (single_turn.events or {})

        local filename = "audit-turn-" .. single_turn.id .. "-" .. ts .. ".md"
        local filepath = dir .. "/" .. filename
        local f = io.open(filepath, "w")
        if not f then
            return { error = "Could not create report file at: " .. filepath }
        end

        local status_str = (single_turn.status == "in_progress") and "In Progress" or "Completed"

        f:write("# Turn #" .. single_turn.id .. " Audit Report — Security & Execution Snapshot\n\n")
        f:write("- **Turn Number:** #" .. single_turn.id .. "\n")
        f:write("- **Status:** " .. status_str .. "\n")
        f:write("- **Turn Timestamp:** `" .. (single_turn.timestamp or "") .. "`\n")
        f:write("- **Export Time:** " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        f:write("- **Session ID:** `" .. tostring(summary.session_uuid) .. "`\n\n")

        f:write("## User Instruction\n\n")
        local prompt_text = (single_turn.prompt and single_turn.prompt ~= "") and single_turn.prompt or (single_turn.raw_prompt or "*(No instruction text recorded)*")
        f:write("```text\n" .. prompt_text .. "\n```\n\n")

        f:write("## Turn Metrics\n\n")
        f:write("| Metric | Value | Description |\n")
        f:write("|---|---|---|\n")
        f:write("| Total Operations | " .. (single_turn.events_count or #t_events) .. " | Operations recorded in this turn |\n")
        f:write("| Shell Commands | " .. (single_turn.command_count or 0) .. " | Terminal commands executed |\n")
        f:write("| File Edits | " .. (single_turn.mutation_count or 0) .. " | File additions and replacements |\n")
        f:write("| Codebase Inspections | " .. (single_turn.inspect_count or 0) .. " | File reads, searches, and directory listings |\n")
        f:write("| Reasoning Passes | " .. (single_turn.thought_count or 0) .. " | Agent cognitive reasoning passes |\n\n")

        f:write("## Modified Files in Turn #" .. single_turn.id .. "\n\n")
        if single_turn.files_modified_list and #single_turn.files_modified_list > 0 then
            for _, file in ipairs(single_turn.files_modified_list) do
                f:write("- `" .. file .. "`\n")
            end
            f:write("\n")
        else
            f:write("*(No files modified in this turn)*\n\n")
        end

        if single_turn.latest_thought and single_turn.latest_thought ~= "" then
            f:write("## Agent Strategy & Reasoning\n\n")
            f:write("```text\n" .. single_turn.latest_thought .. "\n```\n\n")
        end

        -- Cybersecurity Alerts & Incident Flags
        local alert_count = 0
        for _, ev in ipairs(t_events) do
            if ev.risk_level and ev.risk_level ~= "safe" then
                alert_count = alert_count + 1
            end
        end

        f:write("## Security Flags & Threat Assessment\n\n")
        if alert_count > 0 then
            f:write("| Step | Risk Level | Operation | Rule & Explanation |\n")
            f:write("|---|---|---|---|\n")
            for _, ev in ipairs(t_events) do
                if ev.risk_level and ev.risk_level ~= "safe" then
                    local reasons = table.concat(ev.risk_reasons or {}, "; ")
                    f:write("| `#" .. ev.step .. "` | **" .. ev.risk_level:upper() .. "** | `" .. (ev.tool or ev.category) .. "` | " .. reasons .. " |\n")
                end
            end
            f:write("\n")
        else
            f:write("*(No high-risk security operations or policy flags detected in Turn #" .. single_turn.id .. ")*\n\n")
        end

        -- Shell Commands Executed in Turn (Full Log)
        f:write("## Executed Shell Commands — Turn #" .. single_turn.id .. "\n\n")
        local cmd_count = 0
        for _, ev in ipairs(t_events) do
            if ev.category == "terminal" or ev.tool == "run_command" then
                cmd_count = cmd_count + 1
                f:write("### Command #" .. cmd_count .. " (Step #" .. ev.step .. ")\n\n")
                f:write("- **Timestamp:** `" .. ev.timestamp .. "`\n")
                if ev.cwd and ev.cwd ~= "" then
                    f:write("- **Working Directory:** `" .. ev.cwd .. "`\n")
                end
                if ev.summary and ev.summary ~= ev.details and ev.summary ~= "" then
                    f:write("- **Summary:** " .. ev.summary .. "\n")
                end
                f:write("\n```bash\n" .. ev.details .. "\n```\n\n")
            end
        end

        if cmd_count == 0 then
            f:write("*(No shell commands executed during this turn)*\n\n")
        end

        -- Full Sequential Execution Log
        f:write("## Sequential Execution Log (All " .. #t_events .. " Steps)\n\n")
        for idx, ev in ipairs(t_events) do
            f:write("### " .. idx .. ". Step #" .. ev.step .. " — [" .. (ev.tool or ev.category):upper() .. "] " .. (ev.title or ev.summary) .. "\n\n")
            f:write("- **Timestamp:** `" .. ev.timestamp .. "`\n")
            f:write("- **Category:** `" .. ev.category .. "`\n")
            if ev.cwd and ev.cwd ~= "" then
                f:write("- **Working Directory:** `" .. ev.cwd .. "`\n")
            end
            f:write("- **Action Summary:** " .. ev.summary .. "\n\n")
            if ev.details and ev.details ~= "" and ev.details ~= ev.summary then
                f:write("```text\n" .. ev.details .. "\n```\n\n")
            end
        end

        f:close()

        return {
            status = "ok",
            filename = filename,
            filepath = filepath,
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            total_steps = #t_events,
            turn_id = single_turn.id
        }
    end

    -- Full Session Audit Report
    local radar = M.get_workspace_radar()
    local filename = "audit-session-" .. ts .. ".md"
    local filepath = dir .. "/" .. filename

    local f = io.open(filepath, "w")
    if not f then
        return { error = "Could not create report file at: " .. filepath }
    end

    f:write("# Session Audit Report — Operations & Security Log\n\n")
    f:write("- **Export Time:** " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    f:write("- **Session ID:** `" .. tostring(summary.session_uuid) .. "`\n")
    f:write("- **Total Turns:** " .. tostring(summary.total_turns or 0) .. "\n")
    f:write("- **Total Logged Steps:** " .. tostring(summary.total_steps or 0) .. "\n\n")

    f:write("## Operations Summary\n\n")
    f:write("| Category | Count | Description |\n")
    f:write("|---|---|---|\n")
    f:write("| Shell Commands | " .. tostring(summary.category_counts.terminal or 0) .. " | Command-line executions and process launches |\n")
    f:write("| File Edits | " .. tostring(summary.category_counts.mutation or 0) .. " | File additions, modifications, and replacements |\n")
    f:write("| Codebase Inspections | " .. tostring(summary.category_counts.inspect or 0) .. " | File listings, searches, and reads |\n")
    f:write("| Reasoning Passes | " .. tostring(summary.total_thoughts or 0) .. " | Cognitive analysis and strategy passes |\n")
    f:write("| User Prompts | " .. tostring(summary.category_counts.user or 0) .. " | Instructions from user |\n\n")

    -- Cybersecurity Threats & Incident Flags across session
    -- 1. Secret Scanner Section
    f:write("## 🔑 Secret & Credential Leak Audit\n\n")
    local audit_secrets = (summary.security_audit and summary.security_audit.secrets) or {}
    if #audit_secrets > 0 then
        f:write("| Step | Turn | Type | Masked Preview |\n")
        f:write("| :--- | :--- | :--- | :--- |\n")
        for _, s in ipairs(audit_secrets) do
            f:write(string.format("| #%d | Turn #%d | %s | `%s` |\n", s.step, s.turn_id, s.type, s.preview))
        end
        f:write("\n")
    else
        f:write("*(No exposed API keys, private tokens, or credentials detected in transcript)*\n\n")
    end

    -- 2. Perimeter Escapes Section
    f:write("## 🚧 Workspace Perimeter & Sandbox Escapes\n\n")
    local audit_escapes = (summary.security_audit and summary.security_audit.boundary_escapes) or {}
    if #audit_escapes > 0 then
        f:write("| Step | Turn | Reason | Path / Detail |\n")
        f:write("| :--- | :--- | :--- | :--- |\n")
        for _, b in ipairs(audit_escapes) do
            f:write(string.format("| #%d | Turn #%d | %s | `%s` |\n", b.step, b.turn_id, b.reason, b.cwd or b.target or ""))
        end
        f:write("\n")
    else
        f:write("*(All operations strictly confined within project root: `" .. (summary.workspace_root or "workspace") .. "`)*\n\n")
    end

    -- 4. Indirect Prompt Injections & Jailbreak Audit Section
    f:write("## 🛡️ Indirect Prompt Injection & Jailbreak Audit\n\n")
    local audit_inj = (summary.security_audit and summary.security_audit.injections) or {}
    if #audit_inj > 0 then
        f:write("| Step | Turn | Type | Severity | Source | Evidence Snippet |\n")
        f:write("| :--- | :--- | :--- | :--- | :--- | :--- |\n")
        for _, inj in ipairs(audit_inj) do
            f:write(string.format("| #%d | Turn #%d | %s | **%s** | `%s` | `%s` |\n", inj.step, inj.turn_id, inj.type, inj.severity:upper(), inj.source or "", inj.snippet:gsub("`", "'")))
        end
        f:write("\n")
    else
        f:write("*(Zero indirect prompt injection vectors or jailbreak attempts detected)*\n\n")
    end

    -- 3. Network Egress & Dependencies Section
    f:write("## 🌐 Network Egress & Package Dependencies Log\n\n")
    local audit_egress = (summary.security_audit and summary.security_audit.network_egress) or {}
    local audit_pkgs = (summary.security_audit and summary.security_audit.packages) or {}
    if #audit_egress > 0 or #audit_pkgs > 0 then
        if #audit_egress > 0 then
            f:write("### Outbound Network Calls\n\n")
            f:write("| Step | Turn | Protocol | Destination |\n")
            f:write("| :--- | :--- | :--- | :--- |\n")
            for _, e in ipairs(audit_egress) do
                f:write(string.format("| #%d | Turn #%d | %s | `%s` |\n", e.step, e.turn_id, e.type, e.destination))
            end
            f:write("\n")
        end
        if #audit_pkgs > 0 then
            f:write("### Third-Party Packages Installed\n\n")
            f:write("| Step | Turn | Manager | Package Name |\n")
            f:write("| :--- | :--- | :--- | :--- |\n")
            for _, p in ipairs(audit_pkgs) do
                f:write(string.format("| #%d | Turn #%d | %s | `%s` |\n", p.step, p.turn_id, p.manager, p.package))
            end
            f:write("\n")
        end
    else
        f:write("*(No external network calls or third-party packages recorded)*\n\n")
    end

    f:write("## Security Threat Assessment & Policy Flags\n\n")
    if (summary.security_alerts_count or 0) > 0 then
        f:write("| Turn | Step | Risk Level | Operation | Rule & Security Flag |\n")
        f:write("|---|---|---|---|---|\n")
        for _, t in ipairs(turns) do
            for _, ev in ipairs(t.events or {}) do
                if ev.risk_level and ev.risk_level ~= "safe" then
                    local reasons = table.concat(ev.risk_reasons or {}, "; ")
                    f:write("| Turn " .. t.id .. " | `#" .. ev.step .. "` | **" .. ev.risk_level:upper() .. "** | `" .. (ev.tool or ev.category) .. "` | " .. reasons .. " |\n")
                end
            end
        end
        f:write("\n")
    else
        f:write("*(Zero high-risk security incidents or policy flags detected across this entire session)*\n\n")
    end

    f:write("## Workspace Status\n\n")
    f:write("| Repository | Branch | Uncommitted Changes |\n")
    f:write("|---|---|---|\n")
    for _, repo in ipairs(radar) do
        local status_label = (repo.modified_files == 0) and "Clean" or (repo.modified_files .. " modified")
        f:write("| `" .. repo.name .. "` | `" .. repo.branch .. "` | " .. status_label .. " |\n")
    end
    f:write("\n")

    -- Dedicated Cybersecurity Shell Commands Section: 100% of commands in full
    f:write("## Audit Log: Complete Executed Shell Commands\n\n")
    f:write("All commands executed by the agent in this session are recorded in chronological order without truncation:\n\n")
    local cmd_index = 0
    for _, t in ipairs(turns) do
        local t_events = t.events or {}
        for _, ev in ipairs(t_events) do
            if ev.category == "terminal" and ev.tool == "run_command" then
                cmd_index = cmd_index + 1
                f:write("### Command #" .. cmd_index .. " (Turn " .. t.id .. ", Step #" .. ev.step .. ")\n\n")
                f:write("- **Timestamp:** `" .. ev.timestamp .. "`\n")
                if ev.cwd and ev.cwd ~= "" then
                    f:write("- **Working Directory:** `" .. ev.cwd .. "`\n")
                end
                if ev.summary and ev.summary ~= ev.details and ev.summary ~= "" then
                    f:write("- **Summary:** " .. ev.summary .. "\n")
                end
                f:write("\n```bash\n" .. ev.details .. "\n```\n\n")
            end
        end
    end

    if cmd_index == 0 then
        f:write("*(No shell commands recorded in active turns)*\n\n")
    end

    f:write("## Turn-by-Turn Security Audit Trail\n\n")
    for i = #turns, 1, -1 do
        local t = turns[i]
        local status_str = (t.status == "in_progress") and "In Progress" or "Completed"
        f:write("### Turn " .. t.id .. " — " .. status_str .. "\n\n")
        f:write("- **Timestamp:** `" .. t.timestamp .. "`\n")
        f:write("- **User Prompt:** " .. (t.prompt ~= "" and t.prompt or "*(No text)*") .. "\n")
        f:write("- **Operations:** " .. t.events_count .. " total (" .. t.command_count .. " commands, " .. t.mutation_count .. " file edits, " .. t.inspect_count .. " inspects)\n")
        if t.files_modified_list and #t.files_modified_list > 0 then
            f:write("- **Modified Files:** `" .. table.concat(t.files_modified_list, "`, `") .. "`\n")
        end

        local t_events = t.events or {}
        if #t_events > 0 then
            f:write("\n#### Logged Operations in Turn " .. t.id .. "\n\n")
            for _, ev in ipairs(t_events) do
                f:write("- `#" .. ev.step .. "` [" .. ev.category:upper() .. "] **" .. ev.title .. "**: " .. ev.summary .. "\n")
                if ev.details and ev.details ~= "" and ev.details ~= ev.summary then
                    f:write("  ```text\n  " .. ev.details:gsub("\n", "\n  ") .. "\n  ```\n")
                end
            end
        end
        f:write("\n")
    end

    f:close()

    return {
        status = "ok",
        filename = filename,
        filepath = filepath,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        total_steps = summary.total_steps
    }
end

function M.list_reports()
    local dir = M.get_reports_dir()
    local cmd = "ls -lt \"" .. dir .. "\" 2>/dev/null"
    local p = io.popen(cmd)
    local list = {}
    if p then
        for line in p:lines() do
            local filename = line:match("([^%s]+%.md)$")
            if filename then
                local filepath = dir .. "/" .. filename
                local f = io.open(filepath, "r")
                local size = 0
                if f then
                    size = f:seek("end") or 0
                    f:close()
                end
                table.insert(list, {
                    filename = filename,
                    filepath = filepath,
                    size_kb = math.floor((size / 1024) * 10) / 10,
                    date = filename:gsub("audit%-", ""):gsub("%.md$", ""):gsub("_", " ")
                })
            end
        end
        p:close()
    end
    return list
end

function M.read_report(filename)
    if not filename or filename:find("%.%.") or filename:find("/") or filename:find("\\") then
        return { error = "Invalid filename" }
    end
    local filepath = M.get_reports_dir() .. "/" .. filename
    local f = io.open(filepath, "r")
    if not f then
        return { error = "File not found: " .. filename }
    end
    local content = f:read("*a")
    f:close()
    return {
        filename = filename,
        content = content
    }
end

function M.reveal_report(filename)
    local dir = M.get_reports_dir()
    if filename and filename ~= "" and not filename:find("/") and not filename:find("\\") then
        local target = dir .. "/" .. filename
        os.execute("open -R \"" .. target .. "\" 2>/dev/null || open \"" .. dir .. "\" 2>/dev/null")
    else
        os.execute("open \"" .. dir .. "\" 2>/dev/null")
    end
    return { status = "ok" }
end

M.format_event = format_event
return M
