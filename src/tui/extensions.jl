# ── Extensions Tab ────────────────────────────────────────────────────────────
#
# Tab 9: Managed extension monitoring. Two panes:
#   Pane 1 (left): Extension list with status indicators
#   Pane 2 (right): Detail view for selected extension

# ── View ─────────────────────────────────────────────────────────────────────

function view_extensions(m::KaimonModel, area::Rect, buf::Buffer)
    panes = split_layout(m.extensions_layout, area)
    length(panes) < 2 && return
    render_resize_handles!(buf, m.extensions_layout)

    _view_extensions_list(m, panes[1], buf)
    _view_extensions_detail(m, panes[2], buf)
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
            "Add to ~/.config/kaimon/extensions.json",
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
end

function _ext_status_display(status::Symbol)
    @match status begin
        :running => ("●", tstyle(:success))
        :starting => ("◌", tstyle(:warning))
        :crashed => ("✗", tstyle(:error))
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

    # Actions hint
    if y <= bottom(inner)
        set_string!(
            buf,
            x,
            y,
            "[s]tart  [x]stop  [r]estart",
            tstyle(:text_dim),
        )
    end
end

# ── Keyboard handling ────────────────────────────────────────────────────────

function _handle_extensions_key!(m::KaimonModel, evt::KeyEvent)
    extensions = get_managed_extensions()
    isempty(extensions) && return

    @match evt.char begin
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
    extensions = get_managed_extensions()
    n = length(extensions)
    n == 0 && return

    if fp == 1  # list pane
        @match evt.key begin
            :up => (m.ext_selected = max(1, m.ext_selected - 1))
            :down => (m.ext_selected = min(n, m.ext_selected + 1))
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
