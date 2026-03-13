# ── Extensions Tab ────────────────────────────────────────────────────────────
#
# Tab 9: Managed extension monitoring. Two panes:
#   Pane 1 (left): Extension list with status indicators
#   Pane 2 (right): Detail view for selected extension
#
# Features:
#   [a]dd — register a new extension via path input
#   [d]elete — remove selected extension
#   [s]tart / [x]stop / [r]estart — lifecycle control
#   [Enter] — open full detail view with tool documentation
#   [Esc] — close detail view / cancel flow

# ── View ─────────────────────────────────────────────────────────────────────

function view_extensions(m::KaimonModel, area::Rect, buf::Buffer)
    if m.ext_detail_open
        _view_ext_detail_full(m, area, buf)
    else
        panes = split_layout(m.extensions_layout, area)
        length(panes) < 2 && return
        render_resize_handles!(buf, m.extensions_layout)

        _view_extensions_list(m, panes[1], buf)
        _view_extensions_detail(m, panes[2], buf)
    end

    # Overlay flow modals on top
    if m.ext_flow != :idle
        _view_ext_flow(m, area, buf)
    end
end

# ── Left pane: Extension list ────────────────────────────────────────────────

function _view_extensions_list(m::KaimonModel, area::Rect, buf::Buffer)
    extensions = get_managed_extensions()

    block = Block(
        title = "Extensions ($(length(extensions)))",
        border_style = _pane_border(m, 9, 1),
        title_style = _pane_title(m, 9, 1),
    )
    inner = render(block, area, buf)
    inner.width < 4 && return

    if isempty(extensions)
        set_string!(buf, inner.x + 1, inner.y, "No extensions configured.", tstyle(:text_dim))
        set_string!(
            buf,
            inner.x + 1,
            inner.y + 1,
            "Press [a] to add an extension",
            tstyle(:text_dim),
        )
        return
    end

    y = inner.y
    for (i, ext) in enumerate(extensions)
        y > bottom(inner) && break
        ns = ext.config.manifest.namespace
        status_icon, status_style = _ext_status_display(ext.status)

        selected = i == m.ext_selected
        line_style = selected ? tstyle(:accent, bold = true) : tstyle(:text)

        # Status indicator + name
        set_string!(buf, inner.x + 1, y, status_icon, status_style)
        set_string!(buf, inner.x + 3, y, ns, line_style)

        # Right-aligned info
        info = _ext_short_info(ext)
        info_x = inner.x + inner.width - length(info) - 1
        if info_x > inner.x + 3 + length(ns)
            set_string!(buf, info_x, y, info, tstyle(:text_dim))
        end

        y += 1
    end

    # Actions hint at bottom of list pane
    hint_y = bottom(inner)
    if hint_y > y
        set_string!(
            buf,
            inner.x + 1,
            hint_y,
            "[a]dd [d]el [e]nable [t]auto [s] [x] [r]",
            tstyle(:text_dim),
        )
    end
end

function _ext_status_display(status::Symbol)
    @match status begin
        :running => ("⬤", tstyle(:success))
        :starting => ("◌", tstyle(:warning))
        :crashed => ("⬤", tstyle(:error))
        :stopping => ("◌", tstyle(:warning))
        :stopped => ("○", tstyle(:text_dim))
        _ => ("?", tstyle(:text_dim))
    end
end

function _ext_short_info(ext::ManagedExtension)
    if ext.status == :running
        uptime = format_uptime(time() - ext.started_at)
        return uptime
    elseif ext.status == :crashed
        return "crashed (×$(ext.restart_count))"
    elseif ext.status == :starting
        return "starting…"
    else
        return ""
    end
end

# ── Right pane: Extension detail ─────────────────────────────────────────────

function _view_extensions_detail(m::KaimonModel, area::Rect, buf::Buffer)
    extensions = get_managed_extensions()

    block = Block(
        title = "Detail",
        border_style = _pane_border(m, 9, 2),
        title_style = _pane_title(m, 9, 2),
    )
    inner = render(block, area, buf)
    inner.width < 4 && return

    if isempty(extensions) || m.ext_selected < 1 || m.ext_selected > length(extensions)
        set_string!(buf, inner.x + 1, inner.y, "Select an extension.", tstyle(:text_dim))
        return
    end

    ext = extensions[m.ext_selected]
    manifest = ext.config.manifest
    entry = ext.config.entry
    y = inner.y
    x = inner.x + 1
    w = inner.width - 2
    label_w = 14

    # Name / namespace
    set_string!(buf, x, y, rpad("Namespace", label_w), tstyle(:text_dim))
    set_string!(buf, x + label_w, y, manifest.namespace, tstyle(:accent, bold = true))
    y += 1

    # Module
    set_string!(buf, x, y, rpad("Module", label_w), tstyle(:text_dim))
    set_string!(buf, x + label_w, y, manifest.module_name, tstyle(:text))
    y += 1

    # Project path
    set_string!(buf, x, y, rpad("Project", label_w), tstyle(:text_dim))
    path_display = _short_path(entry.project_path)
    set_string!(buf, x + label_w, y, first(path_display, w - label_w), tstyle(:text))
    y += 1

    # Description (if present)
    if !isempty(manifest.description)
        set_string!(buf, x, y, rpad("Description", label_w), tstyle(:text_dim))
        desc_avail = w - label_w
        desc_text = first(manifest.description, desc_avail)
        set_string!(buf, x + label_w, y, desc_text, tstyle(:text))
        y += 1
        # Wrap remaining description
        remaining = manifest.description
        if length(remaining) > desc_avail
            remaining = remaining[nextind(remaining, 0, desc_avail + 1):end]
            while !isempty(remaining) && y <= bottom(inner)
                chunk = first(remaining, desc_avail)
                set_string!(buf, x + label_w, y, chunk, tstyle(:text))
                y += 1
                if length(remaining) > desc_avail
                    remaining = remaining[nextind(remaining, 0, desc_avail + 1):end]
                else
                    break
                end
            end
        end
    end

    # Status
    status_icon, status_style = _ext_status_display(ext.status)
    set_string!(buf, x, y, rpad("Status", label_w), tstyle(:text_dim))
    set_string!(buf, x + label_w, y, "$status_icon $(ext.status)", status_style)
    y += 1

    # PID
    pid_str = if ext.process !== nothing && process_running(ext.process)
        string(getpid(ext.process))
    else
        "—"
    end
    set_string!(buf, x, y, rpad("PID", label_w), tstyle(:text_dim))
    set_string!(buf, x + label_w, y, pid_str, tstyle(:text))
    y += 1

    # Uptime / restart count
    if ext.status == :running
        set_string!(buf, x, y, rpad("Uptime", label_w), tstyle(:text_dim))
        set_string!(buf, x + label_w, y, format_uptime(time() - ext.started_at), tstyle(:text))
        y += 1
    end

    set_string!(buf, x, y, rpad("Restarts", label_w), tstyle(:text_dim))
    set_string!(buf, x + label_w, y, string(ext.restart_count), tstyle(:text))
    y += 1

    # Gate session
    set_string!(buf, x, y, rpad("Session", label_w), tstyle(:text_dim))
    sess = isempty(ext.session_key) ? "—" : ext.session_key
    set_string!(buf, x + label_w, y, sess, tstyle(:text))
    y += 1

    # Config flags
    set_string!(buf, x, y, rpad("Enabled", label_w), tstyle(:text_dim))
    set_string!(
        buf,
        x + label_w,
        y,
        entry.enabled ? "yes" : "no",
        tstyle(entry.enabled ? :success : :text_dim),
    )
    y += 1

    set_string!(buf, x, y, rpad("Auto-start", label_w), tstyle(:text_dim))
    set_string!(
        buf,
        x + label_w,
        y,
        entry.auto_start ? "yes" : "no",
        tstyle(entry.auto_start ? :success : :text_dim),
    )
    y += 2

    # Tools function
    set_string!(buf, x, y, rpad("Tools fn", label_w), tstyle(:text_dim))
    set_string!(buf, x + label_w, y, manifest.tools_function, tstyle(:text))
    y += 2

    # Recent errors
    if !isempty(ext.error_log)
        set_string!(buf, x, y, "Recent Errors:", tstyle(:error, bold = true))
        y += 1
        for err in ext.error_log[max(1, end - 4):end]
            y > bottom(inner) && break
            set_string!(buf, x + 1, y, first(err, w - 2), tstyle(:error))
            y += 1
        end
        y += 1
    end

end

# ── Full detail view (Enter to expand) ──────────────────────────────────────

function _view_ext_detail_full(m::KaimonModel, area::Rect, buf::Buffer)
    _sync_ext_detail_pane!(m, area)
    pane = m.ext_detail_pane
    pane === nothing && return

    block = Block(
        title = "Extension Detail — [Esc] close",
        border_style = tstyle(:accent, bold = true),
        title_style = tstyle(:accent, bold = true),
    )
    inner = render(block, area, buf)
    inner.width < 4 && return

    render(pane, inner, buf)
end

"""Build or refresh the ScrollPane for the full extension detail view."""
function _sync_ext_detail_pane!(m::KaimonModel, area::Rect)
    extensions = get_managed_extensions()
    if isempty(extensions) || m.ext_selected < 1 || m.ext_selected > length(extensions)
        m.ext_detail_pane = nothing
        return
    end

    ext = extensions[m.ext_selected]
    lines = _build_ext_detail_lines(ext, m.conn_mgr)

    if m.ext_detail_pane === nothing
        m.ext_detail_pane = ScrollPane(Vector{Span}[]; following = false)
    end

    pane = m.ext_detail_pane::ScrollPane
    # Rebuild content each frame (tools/status may change)
    content = pane.content::Vector{Vector{Span}}
    empty!(content)
    for (text, style) in lines
        push!(content, [Span(text, style)])
    end
end

"""Build styled content lines for the full extension detail view."""
function _build_ext_detail_lines(ext::ManagedExtension, conn_mgr)
    lines = Tuple{String,Style}[]
    manifest = ext.config.manifest
    entry = ext.config.entry

    # Header
    push!(lines, ("$(manifest.module_name) — $(manifest.namespace)", tstyle(:accent, bold = true)))
    push!(lines, ("═" ^ 60, tstyle(:border)))

    # Description
    if !isempty(manifest.description)
        # Word-wrap description at ~70 chars
        for line in _wrap_text(manifest.description, 70)
            push!(lines, (line, tstyle(:text)))
        end
        push!(lines, ("", Style()))
    end

    # Status summary
    status_icon, _ = _ext_status_display(ext.status)
    pid_str = if ext.process !== nothing && Base.process_running(ext.process)
        string(getpid(ext.process))
    else
        "—"
    end
    uptime_str = ext.status == :running ? format_uptime(time() - ext.started_at) : "—"

    push!(lines, ("Status: $status_icon $(ext.status)    PID: $pid_str    Uptime: $uptime_str", tstyle(:text)))
    push!(lines, ("Project: $(_short_path(entry.project_path))", tstyle(:text_dim)))
    push!(lines, ("", Style()))

    # Tool documentation
    conn = _find_ext_connection(ext, conn_mgr)
    if conn !== nothing && !isempty(conn.session_tools)
        tools = conn.session_tools
        push!(lines, ("Tools ($(length(tools))):", tstyle(:accent, bold = true)))
        push!(lines, ("─" ^ 40, tstyle(:border)))

        for tool in tools
            name = get(tool, "name", "unknown")
            desc = get(tool, "description", "")
            args = get(tool, "arguments", Dict{String,Any}[])

            push!(lines, ("", Style()))
            push!(lines, ("▸ $(manifest.namespace).$name", tstyle(:accent, bold = true)))

            # Docstring (word-wrapped)
            if !isempty(desc)
                for line in _wrap_text(desc, 68)
                    push!(lines, ("  $line", tstyle(:text)))
                end
            end

            # Parameters
            if !isempty(args)
                push!(lines, ("", Style()))
                push!(lines, ("  Parameters:", tstyle(:text_dim)))
                for arg in args
                    arg_name = get(arg, "name", "?")
                    type_meta = get(arg, "type_meta", nothing)
                    arg_type = if type_meta isa Dict
                        get(type_meta, "julia_type", "Any")
                    elseif type_meta isa String
                        type_meta
                    else
                        "Any"
                    end
                    required = get(arg, "required", false)
                    is_kwarg = get(arg, "is_kwarg", true)

                    req_marker = required ? " (required)" : ""
                    push!(lines, ("    $arg_name::$arg_type$req_marker", tstyle(:text)))
                end
            end
        end
    elseif conn !== nothing
        push!(lines, ("Tools: (none registered)", tstyle(:text_dim)))
    else
        push!(lines, ("Tools: waiting for gate connection...", tstyle(:warning)))
    end

    # Errors
    if !isempty(ext.error_log)
        push!(lines, ("", Style()))
        push!(lines, ("Recent Errors:", tstyle(:error, bold = true)))
        for err in ext.error_log[max(1, end - 4):end]
            push!(lines, ("  $err", tstyle(:error)))
        end
    end

    # Log output (tail of log file)
    if isfile(ext.log_file)
        try
            log_lines = readlines(ext.log_file)
            if !isempty(log_lines)
                push!(lines, ("", Style()))
                push!(lines, ("Log Output (last 30 lines):", tstyle(:accent, bold = true)))
                push!(lines, ("─" ^ 40, tstyle(:border)))
                for line in log_lines[max(1, end - 29):end]
                    push!(lines, (line, tstyle(:text_dim)))
                end
            end
        catch
        end
    end

    return lines
end

"""Find the REPLConnection matching this extension's namespace."""
function _find_ext_connection(ext::ManagedExtension, conn_mgr)
    conn_mgr === nothing && return nothing
    ns = ext.config.manifest.namespace
    for conn in connected_sessions(conn_mgr)
        if conn.namespace == ns
            return conn
        end
    end
    return nothing
end

"""Word-wrap text to a maximum line width."""
function _wrap_text(text::String, max_width::Int)
    lines = String[]
    for paragraph in split(text, '\n')
        if isempty(paragraph)
            push!(lines, "")
            continue
        end
        words = split(paragraph)
        current = ""
        for word in words
            if isempty(current)
                current = string(word)
            elseif length(current) + 1 + length(word) <= max_width
                current *= " " * string(word)
            else
                push!(lines, current)
                current = string(word)
            end
        end
        !isempty(current) && push!(lines, current)
    end
    return lines
end

# ── Extension flow: add / remove ────────────────────────────────────────────

function begin_ext_add!(m::KaimonModel)
    m.ext_flow = :add_path
    m.ext_path_input = TextInput(text = string(homedir()) * "/", label = "Path: ", tick = m.tick)
end

function begin_ext_remove!(m::KaimonModel)
    ext = _get_selected_ext(m)
    ext === nothing && return
    m.flow_modal_selected = :cancel
    m.ext_flow = :remove_confirm
end

function execute_ext_add!(m::KaimonModel)
    try
        path = normalize_path(Tachikoma.text(m.ext_path_input))
        isdir(path) || error("Directory not found: $path")

        # Validate kaimon.toml exists and is parseable
        manifest = parse_extension_manifest(path)

        # Check for duplicates (normalize existing paths for reliable comparison)
        existing = load_extensions_config()
        for e in existing
            existing_path = normalize_path(e.project_path)
            if existing_path == path
                error("Extension already registered: $(_short_path(path))")
            end
        end

        # Add to extensions.json
        new_entry = ExtensionEntry(path, true, true)
        push!(existing, new_entry)
        save_extensions_config(existing)

        # Add to MANAGED_EXTENSIONS and spawn
        config = ExtensionConfig(new_entry, manifest)
        ext = ManagedExtension(config)
        lock(MANAGED_EXTENSIONS_LOCK) do
            push!(MANAGED_EXTENSIONS, ext)
        end
        spawn_extension!(ext)

        m.ext_flow_message = "Registered '$(manifest.namespace)'\nfrom $(_short_path(path))\n\nExtension is starting..."
        m.ext_flow_success = true
        _push_log!(:info, "Extension '$(manifest.namespace)' registered from $path")
    catch e
        m.ext_flow_message = "Error: $(sprint(showerror, e))"
        m.ext_flow_success = false
    end
    m.ext_flow = :add_result
end

function execute_ext_remove!(m::KaimonModel)
    ext = _get_selected_ext(m)
    ext === nothing && return

    try
        ns = ext.config.manifest.namespace
        project_path = ext.config.entry.project_path

        # Stop the extension
        if ext.status in (:running, :starting, :crashed)
            stop_extension!(ext)
        end

        # Remove from MANAGED_EXTENSIONS
        lock(MANAGED_EXTENSIONS_LOCK) do
            filter!(e -> e !== ext, MANAGED_EXTENSIONS)
        end

        # Remove from extensions.json
        entries = load_extensions_config()
        filter!(e -> e.project_path != project_path, entries)
        save_extensions_config(entries)

        # Adjust selection
        n = length(get_managed_extensions())
        m.ext_selected = clamp(m.ext_selected, 1, max(1, n))

        m.ext_flow_message = "Removed '$(ns)'"
        m.ext_flow_success = true
        _push_log!(:info, "Extension '$ns' removed")
    catch e
        m.ext_flow_message = "Error: $(sprint(showerror, e))"
        m.ext_flow_success = false
    end
    m.ext_flow = :remove_result
end

# ── Flow rendering ──────────────────────────────────────────────────────────

function _view_ext_flow(m::KaimonModel, area::Rect, buf::Buffer)
    _dim_area!(buf, area)

    if m.ext_flow == :add_path
        if m.ext_path_input !== nothing
            m.ext_path_input.tick = m.tick
        end
        _render_text_input_modal(
            buf,
            area,
            "Add Extension",
            "Enter project path (must contain kaimon.toml):",
            m.ext_path_input,
            "[Enter] confirm  [Tab] complete  [Esc] cancel";
            tick = m.tick,
        )

    elseif m.ext_flow == :add_confirm
        path = Tachikoma.text(m.ext_path_input)
        msg = "Register extension?\n\nPath: $(_short_path(path))"
        # Try to show the namespace
        try
            manifest = parse_extension_manifest(normalize_path(path))
            msg *= "\nNamespace: $(manifest.namespace)"
            msg *= "\nModule: $(manifest.module_name)"
        catch
        end
        render(
            Modal(
                title = "Confirm Registration",
                message = msg,
                confirm_label = "Register",
                cancel_label = "Cancel",
                selected = :confirm,
                tick = m.tick,
            ),
            area,
            buf,
        )

    elseif m.ext_flow == :add_result
        _render_result_modal(buf, area, m.ext_flow_success, m.ext_flow_message; tick = m.tick)

    elseif m.ext_flow == :remove_confirm
        ext = _get_selected_ext(m)
        ns = ext !== nothing ? ext.config.manifest.namespace : "?"
        render(
            Modal(
                title = "Remove Extension",
                message = "Remove '$ns'?\n\nThis will stop the extension and\nremove it from the registry.",
                confirm_label = "Remove",
                cancel_label = "Cancel",
                selected = m.flow_modal_selected,
                tick = m.tick,
            ),
            area,
            buf,
        )

    elseif m.ext_flow == :remove_result
        _render_result_modal(buf, area, m.ext_flow_success, m.ext_flow_message; tick = m.tick)
    end
end

# ── Flow input handling ─────────────────────────────────────────────────────

function _handle_ext_flow_input!(m::KaimonModel, evt::KeyEvent)
    flow = m.ext_flow

    if flow == :add_path
        @match evt.key begin
            :enter => begin
                m.ext_flow = :add_confirm
            end
            :tab => _complete_path!(m.ext_path_input)
            _ => handle_key!(m.ext_path_input, evt)
        end

    elseif flow == :add_confirm
        @match evt.key begin
            :enter => execute_ext_add!(m)
            :escape => (m.ext_flow = :idle)
            _ => nothing
        end

    elseif flow == :add_result
        # Errors require Enter to dismiss, success closes on any key
        (m.ext_flow_success || evt.key == :enter) && (m.ext_flow = :idle)

    elseif flow == :remove_confirm
        @match evt.key begin
            :left || :right => begin
                m.flow_modal_selected =
                    m.flow_modal_selected == :cancel ? :confirm : :cancel
            end
            :enter => begin
                m.flow_modal_selected == :confirm ? execute_ext_remove!(m) :
                (m.ext_flow = :idle)
            end
            :escape => (m.ext_flow = :idle)
            _ => nothing
        end

    elseif flow == :remove_result
        (m.ext_flow_success || evt.key == :enter) && (m.ext_flow = :idle)
    end
end

# ── Toggle enabled / auto_start ──────────────────────────────────────────────

function _toggle_ext_field!(m::KaimonModel, field::Symbol)
    ext = _get_selected_ext(m)
    ext === nothing && return

    old_entry = ext.config.entry
    new_enabled = field == :enabled ? !old_entry.enabled : old_entry.enabled
    new_auto = field == :auto_start ? !old_entry.auto_start : old_entry.auto_start
    new_entry = ExtensionEntry(old_entry.project_path, new_enabled, new_auto)
    ext.config = ExtensionConfig(new_entry, ext.config.manifest)

    # Persist to extensions.json
    entries = load_extensions_config()
    for (i, e) in enumerate(entries)
        norm = normalize_path(e.project_path)
        ext_norm = normalize_path(old_entry.project_path)
        if norm == ext_norm
            entries[i] = new_entry
            break
        end
    end
    save_extensions_config(entries)

    # Side effects
    if field == :enabled
        if !new_enabled && ext.status in (:running, :starting)
            stop_extension!(ext)
        elseif new_enabled && new_auto && ext.status == :stopped
            spawn_extension!(ext)
        end
    end
end

# ── Keyboard handling ────────────────────────────────────────────────────────

function _handle_extensions_key!(m::KaimonModel, evt::KeyEvent)
    # Flow captures all input
    if m.ext_flow != :idle
        _handle_ext_flow_input!(m, evt)
        return
    end

    @match evt.char begin
        'a' => begin_ext_add!(m)
        'd' => begin_ext_remove!(m)
        'e' => _toggle_ext_field!(m, :enabled)
        't' => _toggle_ext_field!(m, :auto_start)
        's' => begin
            ext = _get_selected_ext(m)
            ext !== nothing && ext.status == :stopped && spawn_extension!(ext)
        end
        'x' => begin
            ext = _get_selected_ext(m)
            ext !== nothing && ext.status in (:running, :starting, :crashed) &&
                stop_extension!(ext)
        end
        'r' => begin
            ext = _get_selected_ext(m)
            ext !== nothing && restart_extension!(ext)
        end
        _ => nothing
    end
end

function _handle_extensions_nav!(m::KaimonModel, evt::KeyEvent, fp::Int)
    # Flow captures all input
    if m.ext_flow != :idle
        _handle_ext_flow_input!(m, evt)
        return
    end

    # Detail view scroll
    if m.ext_detail_open
        pane = m.ext_detail_pane
        pane !== nothing && handle_key!(pane, evt)
        return
    end

    extensions = get_managed_extensions()
    n = length(extensions)
    n == 0 && return

    if fp == 1  # list pane
        @match evt.key begin
            :up => (m.ext_selected = max(1, m.ext_selected - 1))
            :down => (m.ext_selected = min(n, m.ext_selected + 1))
            :enter => begin
                m.ext_detail_open = true
                m.ext_detail_pane = nothing  # force rebuild
            end
            _ => nothing
        end
    elseif fp == 2  # detail pane in two-pane mode
        @match evt.key begin
            :enter => begin
                m.ext_detail_open = true
                m.ext_detail_pane = nothing  # force rebuild
            end
            _ => nothing
        end
    end
end

function _get_selected_ext(m::KaimonModel)
    exts = lock(MANAGED_EXTENSIONS_LOCK) do
        copy(MANAGED_EXTENSIONS)
    end
    if m.ext_selected >= 1 && m.ext_selected <= length(exts)
        # Return the actual (mutable) reference from the global list
        return lock(MANAGED_EXTENSIONS_LOCK) do
            MANAGED_EXTENSIONS[m.ext_selected]
        end
    end
    return nothing
end
