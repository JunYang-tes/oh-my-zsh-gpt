function end_with() {
  local str=$1
  local suffix=$2
  if [[ "$str" == *"$suffix" ]]; then
    return 0
  else
    return 1
  fi
}
function start_with() {
  local str=$1
  local prefix=$2
  if [[ "$str" == "$prefix"* ]]; then
    return 0
  else
    return 1
  fi
}

function is_question() {
  local cmd=$1
  if start_with "$cmd" ","; then
    return 0
  else
    return 1
  fi
}

log_file=/tmp/gpt.log
function write_log() {
  local msg=$1
  echo $msg >> $log_file
}

random_name=$(mktemp -u /tmp/gpt_messages_XXXXXX.json)

function ask_gpt() {
  local kernel_version=$(uname -r)
  local os_info=$(lsb_release -d | cut -f2)
  local system_prompt="You are a helpful assistant for Linux commands and questions. \
If the user asks for a Linux command, respond only with the command without any explanations. \
The response format for a command is 'cmd: <command content>'. \
For other questions, respond with 'exp: <content>'. \
System information: The current system is running on Linux kernel version $kernel_version, \
with $os_info as the operating system. \
Note: Be aware that user questions may not be isolated and may be related to previous questions."
  local user_prompt="$*"
  local messages='[]'
  if [[ -f $random_name ]]; then
    messages=$(cat $random_name)
  else
    messages=$(echo $messages | jq --arg p "$system_prompt" '[{"role": "system", "content": $p}] + .')
  fi

  messages=$(echo $messages | jq --arg p "$user_prompt" '. + [{"role": "user", "content": $p}]')
 
  local data=$(jq -n --argjson messages "$messages" --arg model "$ZSH_GPT_OPENAI_MODEL" '{"model": $model,"messages": $messages,"temperature": 0.7}')
  local resp=$(curl $ZSH_GPT_OPENAI_HOST/v1/chat/completions -s \
   -H "Content-Type: application/json" \
   -H "Authorization: Bearer $ZSH_GPT_OPENAI_KEY" \
   -d "$data")
  write_log "Request: $data"
  write_log "Response: $resp"
  
  local resp_content=$(echo $resp | jq '.choices[0].message.content' -r)
  echo $resp_content
  messages=$(echo $messages | jq --arg c "$resp_content" '. + [{"role": "assistant", "content": $c}]')
  echo $messages > $random_name
}

function command_not_found_handler() {
  local cmd="$*"
  if is_question "$cmd"; then
  else
    echo "Unknown command: $cmd"
    return 127
  fi
}

function _preexec() {
  local cmd="$1"
  if is_question "$cmd"; then
    q=$cmd[2,-1]
    resp=$(ask_gpt "$q")

    if start_with $resp "cmd:"; then
      print -z $resp[5,-1]
    elif start_with "$resp" "exp:"; then
      local exp=$resp[5,-1]
      echo $exp
    else
      echo "Unknown response: $resp"
    fi
    return 1
  fi
}

add-zsh-hook preexec _preexec
