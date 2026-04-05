# ── HelloExtension TUI Panel ──────────────────────────────────────────────────
#
# Lightweight panel shown inside Kaimon's Extensions tab when the user
# presses [u] on the hello extension. Demonstrates the ext_panel protocol.
#
# Layout:  Greetings | Rolls   (top 2/3)
#          Activity Log        (bottom 1/3)
#
# The panel shows greetings and dice rolls — both from local keypresses
# AND from agent tool calls (pushed via Gate.push_panel()).

using Tachikoma
using Dates

mutable struct HelloPanelState
    greetings::Vector{String}
    rolls::Vector{String}
    activity::Vector{String}   # timestamped activity log
    selected::Int              # 1 = greetings, 2 = rolls, 3 = activity
    tick::Int
    push_count::Int            # total push_panel updates received
    session_key::String        # extension's gate session key
end

const MAX_ACTIVITY = 50

function _log!(state::HelloPanelState, msg::String)
    ts = Dates.format(Dates.now(), "HH:MM:SS")
    push!(state.activity, "[$ts] $msg")
    length(state.activity) > MAX_ACTIVITY && popfirst!(state.activity)
end

function init(ctx)
    state = HelloPanelState(String[], String[], String[], 1, 0, 0, ctx.session_key)
    _log!(state, "Panel initialized — session $(ctx.session_key)")
    _log!(state, "Waiting for Gate.push_panel() events via PUB/SUB...")
    return state
end

function update!(state::HelloPanelState, ctx)
    state.tick = ctx.tick
    # Read pushed state from Gate.push_panel() — arrives via PUB/SUB
    ps = get(ctx._cache, :panel_state, nothing)
    ps === nothing && return
    if haskey(ps, "greetings")
        prev = length(state.greetings)
        state.greetings = ps["greetings"]
        n_new = length(state.greetings) - prev
        if n_new > 0
            state.push_count += 1
            _log!(state, "push #$(state.push_count): greetings updated (+$n_new, total $(length(state.greetings)))")
        end
    end
    if haskey(ps, "rolls")
        prev = length(state.rolls)
        state.rolls = ps["rolls"]
        n_new = length(state.rolls) - prev
        if n_new > 0
            state.push_count += 1
            _log!(state, "push #$(state.push_count): rolls updated (+$n_new, total $(length(state.rolls)))")
        end
    end
end

function view(state::HelloPanelState, area::Tachikoma.Rect, buf::Tachikoma.Buffer)
    outer = Tachikoma.Block(
        title = " Hello Extension [g]reet [r]oll [Tab] switch [Esc] close ",
        border_style = Tachikoma.tstyle(:border_focus),
    )
    content = Tachikoma.render(outer, area, buf)

    # Vertical split: top 2/3 for data panes, bottom 1/3 for activity log
    vsplit = Tachikoma.Layout(
        Tachikoma.Vertical,
        [Tachikoma.Fill(2), Tachikoma.Fill(1)];
        spacing = 0,
    )
    vparts = Tachikoma.split_layout(vsplit, content)
    top_area = vparts[1]
    bot_area = vparts[2]

    # Horizontal split for greetings | rolls
    hsplit = Tachikoma.Layout(
        Tachikoma.Horizontal,
        [Tachikoma.Fill(1), Tachikoma.Fill(1)];
        spacing = 1,
    )
    panes = Tachikoma.split_layout(hsplit, top_area)

    # ── Greetings pane ──
    g_style = state.selected == 1 ? Tachikoma.tstyle(:border_focus) : Tachikoma.tstyle(:border)
    g_block = Tachikoma.Block(title = " Greetings ($(length(state.greetings))) ", border_style = g_style)
    g_inner = Tachikoma.render(g_block, panes[1], buf)
    for (i, msg) in enumerate(Iterators.reverse(state.greetings))
        y = g_inner.y + i - 1
        y > Tachikoma.bottom(g_inner) && break
        Tachikoma.set_string!(buf, g_inner.x, y, msg, Tachikoma.tstyle(:text))
    end

    # ── Rolls pane ──
    r_style = state.selected == 2 ? Tachikoma.tstyle(:border_focus) : Tachikoma.tstyle(:border)
    r_block = Tachikoma.Block(title = " Dice Rolls ($(length(state.rolls))) ", border_style = r_style)
    r_inner = Tachikoma.render(r_block, panes[2], buf)
    for (i, msg) in enumerate(Iterators.reverse(state.rolls))
        y = r_inner.y + i - 1
        y > Tachikoma.bottom(r_inner) && break
        Tachikoma.set_string!(buf, r_inner.x, y, msg, Tachikoma.tstyle(:text))
    end

    # ── Activity log pane ──
    a_style = state.selected == 3 ? Tachikoma.tstyle(:border_focus) : Tachikoma.tstyle(:border)
    status = "ses=$(state.session_key) pushes=$(state.push_count)"
    a_block = Tachikoma.Block(
        title = " Activity Log ($(length(state.activity))) — $status ",
        border_style = a_style,
    )
    a_inner = Tachikoma.render(a_block, bot_area, buf)
    dim_style = Tachikoma.Style(fg=Tachikoma.Color256(245))
    text_style = Tachikoma.tstyle(:text)
    for (i, msg) in enumerate(Iterators.reverse(state.activity))
        y = a_inner.y + i - 1
        y > Tachikoma.bottom(a_inner) && break
        # Dim the timestamp, normal for the message
        bracket_end = findfirst(']', msg)
        if bracket_end !== nothing && bracket_end < length(msg)
            Tachikoma.set_string!(buf, a_inner.x, y, msg[1:bracket_end], dim_style)
            Tachikoma.set_string!(buf, a_inner.x + bracket_end, y, msg[bracket_end+1:end], text_style)
        else
            Tachikoma.set_string!(buf, a_inner.x, y, msg, text_style)
        end
    end
end

function handle_key!(state::HelloPanelState, evt::Tachikoma.KeyEvent)
    if evt.key == :tab
        state.selected = mod1(state.selected + 1, 3)
        return true
    elseif evt.key == :char && evt.char == 'g'
        name = "User#$(rand(100:999))"
        push!(state.greetings, "Hello, $(name)!")
        _log!(state, "local: greeted $(name)")
        return true
    elseif evt.key == :char && evt.char == 'r'
        result = rand(1:6)
        push!(state.rolls, "🎲 Rolled a $result (d6)")
        _log!(state, "local: rolled $result (d6)")
        return true
    end
    return false
end

function cleanup!(state::HelloPanelState, ctx)
end
