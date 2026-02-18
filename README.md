# GalGame Trans Tools

这个工具集包含一些用于处理GalGame文本的工具，大部分是文本处理脚本，例如Siglus Engine的文本格式比较特殊，所以单纯使用文本编辑器进行处理比较麻烦。

本仓库的代码符合lua 5.1标准，可以使用lua或luajit运行。

本仓库的bin目录下携带一个可以在Windows上直接运行的luajit，如果你使用的是Windows系统，可以直接使用bin目录下的luajit来运行脚本，例如：

```bash
./bin/luajit.exe siglus-txt-transform.lua t2j example/siglus-txt-transform/01.ss.txt
```

本仓库代码大多采用TDD + Vibe Coding开发，主要开发助手为Codex + GPT 5.3 Codex。

下面是具体脚本的说明

## siglus-txt-transform

本脚本用于在Siglus Engine的文本格式和JSON格式之间进行转换，适用于游戏文本的提取和回填。

JSON格式采用和GalTrans相同的结构，方便与GalTrans进行配合使用。

具体使用信息参见 [siglus-txt-transform](docs/siglus-txt-transform.md)