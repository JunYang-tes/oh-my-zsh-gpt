## Install

1. Clone to plugins directory of oh-my-zsh
```zsh
cd $ZSH/custom/plugins 
git clone git@github.com:JunYang-tes/oh-my-zsh-gpt.git
```

2. Enable this plugin by editing `~/.zshrc`
```diff
- plugins=(git)
+ plugins=(git oh-my-zsh-gpt)
```

3. Set up environment variables

```
export ZSH_GPT_OPENAI_HOST="https://api.siliconflow.cn/"
export ZSH_GPT_OPENAI_MODEL="deepseek-ai/DeepSeek-V2.5"
export ZSH_GPT_OPENAI_KEY="your key"

```

## Show case
![](./demo.gif)
