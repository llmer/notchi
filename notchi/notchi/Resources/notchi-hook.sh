#!/bin/bash
# Notchi Hook - forwards Claude Code events to Notchi app via Unix socket

export SOCKET_PATH="/tmp/notchi.sock"

# Exit silently if socket doesn't exist (app not running)
[ -S "$SOCKET_PATH" ] || exit 0

# Detect the TTY of the parent process (Claude Code)
HOOK_TTY=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
if [ -n "$HOOK_TTY" ] && [ "$HOOK_TTY" != "??" ]; then
    export HOOK_TTY="/dev/${HOOK_TTY}"
else
    export HOOK_TTY=""
fi

# Parse input and send to socket using Python
/usr/bin/python3 -c "
import json
import os
import socket
import sys

try:
    input_data = json.load(sys.stdin)
except Exception as e:
    print(f'notchi-hook: failed to parse input: {e}', file=sys.stderr)
    sys.exit(0)

hook_event = input_data.get('hook_event_name', '')

hook_tty = os.environ.get('HOOK_TTY', '')

output = {
    'session_id': input_data.get('session_id', ''),
    'cwd': input_data.get('cwd', ''),
    'event': hook_event,
    'status': input_data.get('status', 'unknown'),
    'pid': None,
    'tty': hook_tty if hook_tty else None,
    'permission_mode': input_data.get('permission_mode', 'default')
}

# Pass user prompt directly for UserPromptSubmit
if hook_event == 'UserPromptSubmit':
    prompt = input_data.get('prompt', '')
    if prompt:
        output['user_prompt'] = prompt

tool = input_data.get('tool_name', '')
if tool:
    output['tool'] = tool

tool_id = input_data.get('tool_use_id', '')
if tool_id:
    output['tool_use_id'] = tool_id

tool_input = input_data.get('tool_input', {})
if tool_input:
    output['tool_input'] = tool_input

try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(os.environ['SOCKET_PATH'])
    sock.sendall(json.dumps(output).encode())
    sock.close()
except Exception as e:
    print(f'notchi-hook: socket error: {e}', file=sys.stderr)
    sys.exit(0)
"
