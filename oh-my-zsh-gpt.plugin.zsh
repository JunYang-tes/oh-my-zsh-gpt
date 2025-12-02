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

function gpt-magic-enter() {
  # 检查 Buffer 是否以逗号开头
  if [[ "$BUFFER" == ,* ]]; then
    local query="${BUFFER:1}"
    
    # 将当前行保存到 Zsh 历史记录
    print -s "$BUFFER"
    
    zle -I 

    # --- 修复点 1: 关闭作业监控，消除 [2] 11515 done 这种噪音 ---
    setopt localoptions no_monitor

    # 1. 创建临时文件用于接收结果
    local tmp_resp=$(mktemp)

    # 2. 在后台执行 ask_gpt
    ask_gpt "$query" > "$tmp_resp" &
    local pid=$! # 获取后台进程 ID

    # 3. 定义动画字符 (Braille 风格)
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    # 隐藏光标
    printf "\e[?25l"

    # 4. 循环检查进程
    while kill -0 $pid 2>/dev/null; do
      # --- 修复点 2: 使用 $(( )) 明确告诉 Zsh 这是数学运算 ---
      local idx=$(( i++ % 10 )) 
      # Zsh 字符串截取：${var:offset:length}
      local char="${spin:$idx:1}"
      
      printf "\r\e[36mThinking... %s\e[0m" "$char"
      sleep 0.1
    done

    # 5. 清理现场
    printf "\r\e[2K" # 清除整行
    printf "\e[?25h" # 恢复光标

    # 6. 读取结果
    local resp=$(cat "$tmp_resp")
    rm "$tmp_resp"

    # 7. 处理逻辑
    if [[ "$resp" == cmd:* ]]; then
      local cmd_content="${resp#cmd: }"
      cmd_content="$(echo "$cmd_content" | xargs)" # trim
      
      BUFFER="$cmd_content"
      CURSOR=$#BUFFER 
      
    elif [[ "$resp" == exp:* ]]; then
      BUFFER=""
      zle -I
      echo "${resp#exp: }"
    else
      if [[ -n "$resp" ]]; then
        BUFFER=""
        zle -I
        echo "$resp"
      fi
    fi
    
    #zle redisplay

  else
    # 正常回车
    zle .accept-line
  fi
}

# 注册 Widget (如果你之前运行过，最好重启终端或者重新 source 一下，确保旧的定义被覆盖)
zle -N gpt-magic-enter
bindkey '^M' gpt-magic-enter
