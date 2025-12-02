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
  printf -s "$msg" >> $log_file
  printf -s "\n" >> $log_file
}

random_name=$(mktemp -u /tmp/gpt_messages_XXXXXX.json)

# --- 这里稍微调整一下 ask_gpt，去掉不必要的 sed 转义 ---
# 因为我们现在直接从 buffer 获取原始字符串，不需要处理转义字符
function ask_gpt() {
  local kernel_version=$(uname -r)
  local os_info=$(lsb_release -d 2>/dev/null | cut -f2) # 加了错误屏蔽防止没有lsb_release报错
  local system_prompt="You are a helpful assistant for Linux commands and questions. \
If the user asks for a Linux command, respond only with the command without any explanations. \
The response format for a command is 'cmd: <command content>'. \
For other questions, respond with 'exp: <content>'. \
System information: The current system is running on Linux kernel version $kernel_version, \
with $os_info as the operating system. \
Note: Be aware that user questions may not be isolated and may be related to previous questions."
  
  # 直接使用原始输入，jq -R 会自动安全处理引号
  local user_prompt="$*" 
  
  local messages='[]'
  if [[ -f $random_name ]]; then
    messages=$(cat "$random_name")
    if ! jq empty <<< "$messages" >/dev/null 2>&1; then
      messages='[]'
    fi
  else
    local system_prompt_json=$(echo "$system_prompt" | jq -R .)
    messages=$(echo "$messages" | jq --argjson p "$system_prompt_json" '[{"role": "system", "content": $p}] + .')
  fi

  local user_prompt_json=$(echo "$user_prompt" | jq -R .)
  messages=$(echo "$messages" | jq --argjson p "$user_prompt_json" '. + [{"role": "user", "content": $p}]')
 
  # 请确保 ZSH_GPT_OPENAI_MODEL 等环境变量已设置
  local data=$(jq -n --argjson messages "$messages" --arg model "$ZSH_GPT_OPENAI_MODEL" '{"model": $model,"messages": $messages,"temperature": 0.7}')
  local resp=$(curl -X POST $ZSH_GPT_OPENAI_HOST/v1/chat/completions -s \
   -H "Content-Type: application/json" \
   -H "Authorization: Bearer $ZSH_GPT_OPENAI_KEY" \
   -d "$data")
  
  write_log "Request: $data"
  write_log "Response: $resp"
  
  local resp_content=$(printf '%s' "$resp" | jq -r '.choices[0].message.content')
  echo "$resp_content"
  
  # 更新上下文
  messages=$(echo "$messages" | jq --argjson resp_json "$resp" '. + [{"role": "assistant", "content": $resp_json.choices[0].message.content}]')
  printf '%s' "$messages" > "$random_name"
}

# --- 核心修改：自定义回车键 Widget ---

function gpt-magic-enter() {
  # 检查 Buffer 是否以逗号开头
  if [[ "$BUFFER" == ,* ]]; then
    # 1. 获取查询内容（去掉开头的逗号）
    local query="${BUFFER:1}"
    
    # 2. 将当前行保存到 Zsh 历史记录中，方便按上箭头找回
    print -s "$BUFFER"
    
    # 3. 模拟回车换行效果，打印用户输入的内容
    echo # 输出一个换行
    echo "> $query" # 可选：回显一下查询内容
    
    # 4. 通知 ZLE 我们要进行输出，重置提示符位置
    zle -I 
    
    # 5. 调用 GPT
    # 这里会阻塞直到 GPT 返回。为了用户体验，你也可以考虑在这里加个 "Thinking..." 的提示
    local resp=$(ask_gpt "$query")
    
    # 6. 处理返回结果
    if [[ "$resp" == cmd:* ]]; then
      # 如果是命令，将 Buffer 替换为该命令，让用户决定是否执行
      # 这里的 ${resp#cmd: } 是去除前缀
      local cmd_content="${resp#cmd: }"
      # 去除可能存在的首尾空白
      cmd_content="$(echo "$cmd_content" | xargs)"
      
      BUFFER="$cmd_content"
      CURSOR=$#BUFFER # 光标移动到末尾
      
    elif [[ "$resp" == exp:* ]]; then
      # 如果是解释，直接打印出来，并清空当前行
      echo "${resp#exp: }"
      BUFFER="" 
      
    else
      # 未知格式，直接打印
      echo "$resp"
      BUFFER=""
    fi
    
    # 7. 如果我们只是打印了解释，就不需要执行任何命令了，保持 Buffer 为空或新命令即可
    # 不需要调用 zle .accept-line，因为我们已经处理完了
    
  else
    # 如果不是逗号开头，执行默认的回车行为（Zsh 的标准解析和执行）
    zle .accept-line
  fi
}

# 注册 Widget
zle -N gpt-magic-enter

# 绑定回车键到这个 Widget
bindkey '^M' gpt-magic-enter
