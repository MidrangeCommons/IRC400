# Data layout

Field-level reference for the IRC client's persistent state. Used by the network engine, the chat panel controller, and the maintenance helpers.

## `IRCCONF` data area — CHAR(512)

Single shared data area holding connection state, settings, and inter-job cursors. Both `IRCNETD` (engine) and `IRCCHATC` (UI) read it; writes are tagged below as **E** (engine) or **U** (UI).

| Pos | Len | Field | Writer | Notes |
|---|---|---|---|---|
| 1 | 1 | `conn_state` | E | `0`=disconnected, `1`=connecting, `2`=connected, `3`=disconnecting |
| 2 | 1 | `disconnect_requested` | U | `0`/`1` — UI sets to ask engine to quit |
| 3 | 1 | `autoreconnect` | U | `0`/`1` — from settings |
| 4 | 1 | `colors_enabled` | U | `0`/`1` — from settings |
| 5 | 1 | `input_mode` | U | `0`=1-line, `1`=half-screen (F11 toggle) |
| 6 | 4 | `last_error` | E | numeric error code (zoned) |
| 10 | 6 | _reserved_ | — | |
| 16 | 64 | `server_host` | U | current server host or IP |
| 80 | 5 | `server_port` | U | TCP port (zoned) |
| 85 | 32 | `nick` | E | actual current nick (engine updates on `001`/`NICK`) |
| 117 | 32 | `nick_alt` | U | fallback if nick taken |
| 149 | 32 | `username` | U | IRC USER param |
| 181 | 64 | `realname` | U | IRC USER realname |
| 245 | 4 | `current_window` | U | which window the chat panel is showing |
| 249 | 9 | `next_msgbuf_seq` | E | next seq the engine will assign on append |
| 258 | 9 | `last_painted_seq` | U | UI's high-water mark for "what I've already shown" |
| 267 | 9 | `msgbuf_low_water` | E | oldest live seq after circular trim |
| 276 | 9 | `msgbuf_high_water` | E | newest live seq |
| 285 | 228 | _reserved_ | — | room to grow without breaking layout |

The engine and UI cooperate on the message buffer through `next_msgbuf_seq` (engine increments) and `last_painted_seq` (UI bumps). The low/high water fields make the circular wrap (Phase 10) tractable without scanning the whole PF.

## `MSGBUF` PF — circular message buffer

| Field | Type | Purpose |
|---|---|---|
| `MBSEQ` | `9P 0` | Monotonic line sequence (key, ascending) |
| `MBWIN` | `4P 0` | Window seq: `0`=status, `1+`=channels/PMs |
| `MBTS` | `8A` | `HH:MM:SS` local time |
| `MBKIND` | `1A` | `M`=msg `N`=notice `S`=system `A`=action `J`=join `P`=part `Q`=quit `T`=topic |
| `MBNICK` | `32A` | sender nick (blank for system lines) |
| `MBNCOL` | `1A` | nick color: `W`/`R`/`G`/`Y`/`B`/`P`/`T` (one of the 7 5250 colors, derived from a hash of the nick) |
| `MBFRAGS` | `512A CCSID(65535)` | IRCFMT-encoded fragment list |

**Fragment encoding** (`MBFRAGS`):

```
record    := fragment+ 0x00
fragment  := 0x01 <color:1> <attr:1> <len:1> <text:len>
color     := 'W' | 'R' | 'G' | 'Y' | 'B' | 'P' | 'T' | '_' (default)
attr      := bitmask: 0x01=bold(HI) 0x02=underline(UL) 0x04=reverse(RI)
text      := raw bytes (ASCII, will be ASCII→EBCDIC translated by the chat panel for display)
```

`len` is one byte (max fragment text 255) — fragments shorter than `len` are blank-padded by the chat panel, longer source runs are split into multiple fragments by `IRCFMT`.

## `IRCSRVR` PF — saved server list

Mirrors the NTP `NTPSRVR` shape for the user-facing "Work with IRC servers" panel.

| Field | Type | Purpose |
|---|---|---|
| `ISSEQ` | `3P 0` | Sequence/priority (key) |
| `ISNAME` | `32A` | Friendly name (e.g. `Libera`) |
| `ISHOST` | `64A` | Host or IP |
| `ISPORT` | `5P 0` | TCP port (default 6667) |
| `ISNICK` | `32A` | Preferred nick on this network |
| `ISACT` | `1A` | `1`=active, `0`=inactive |
| `ISDESC` | `30A` | Description |

## `IRCWINR` PF — active windows table

One record per open window. The status window (`WRSEQ=0`) is created on connect; channel and PM windows are added/removed by the engine on JOIN/PART/PRIVMSG.

| Field | Type | Purpose |
|---|---|---|
| `WRSEQ` | `4P 0` | Window sequence (key); `0`=status |
| `WRKIND` | `1A` | `S`=status, `C`=channel, `P`=private message |
| `WRNAME` | `64A` | Channel name (with `#`) or nick for PM |
| `WRTOPIC` | `256A` | Channel topic (empty for PMs/status) |
| `WRUNREAD` | `5P 0` | Unread line count since last switch |
| `WROPEN` | `1A` | `1`=open, `0`=closed (history kept in `MSGBUF`) |

## Data queues

| Object | Max entry | Direction | Purpose |
|---|---|---|---|
| `IRCOUTQ` | 512 bytes | UI → engine | Outbound IRC command lines, e.g. `JOIN #foo` or `PRIVMSG #foo :hi` |
| `IRCEVTQ` | 1 byte | engine → UI | Wakeup pings — engine sends one byte after every `MSGBUF` append so the UI's `INVITE` read returns promptly without waiting for its 2 s timer |
