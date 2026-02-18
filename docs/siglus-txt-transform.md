# Siglus Txt Scripts To Json and Resume

这个脚本是用来将siglus游戏引擎提取的TXT脚本转换为GalTrans易使用JSON脚本，然后再将其JSON脚本转回siglus引擎能够识别的TXT脚本的功能

该脚本使用的文件为 `siglus-txt-transform.lua`，JSON库为 `libs/dkjson.lua`。

兼容环境：
- Lua 5.1
- Lua 5.2
- Lua 5.3
- Lua 5.4
- LuaJIT

命令通用格式：

```bash
lua siglus-txt-transform.lua <mode> ...
```

也可以直接使用 LuaJIT：

```bash
luajit siglus-txt-transform.lua <mode> ...
```

其拥有两个功能：

1. txt to json

在 example/siglus-txt-transform/01.ss.txt中有一个例子，其特点为前面是标识符，后面是文本，每两行对应Json一个object，其转换后的例子为example/siglus-txt-transform/01.ss.json

这个功能有两个实现：

```bash
luajit siglus-txt-transform.lua t2j example/siglus-txt-transform/01.ss.txt [example/siglus-txt-transform/01.ss.json]
# 方括号内为可选项，若不指定则默认输出到当前目录下的同名json文件
```

```bash
luajit siglus-txt-transform.lua t2j example/siglus-txt-transform example/siglus-txt-transform/output
# 该命令会将example/siglus-txt-transform目录下的所有txt文件转换为json文件，并输出到example/siglus-txt-transform/output目录下
```

2. json to txt
在 example/siglus-txt-transform/01.ss.json中有一个例子，其转换后的例子为example/siglus-txt-transform/01.ss.txt

由于原文本具有标识符，因此在转换过程中必须给出最初的txt文件，以便从中提取标识符进行转换，因此该功能的命令格式如下：

```bash
luajit siglus-txt-transform.lua j2t example/siglus-txt-transform/01.ss.txt example/siglus-txt-transform/01.ss.json [example/siglus-transform/01.ss.txt]
# 方括号内为可选项，若不指定则为同目录下原文件名.out.txt
```

```bash
luajit siglus-txt-transform.lua j2t example/siglus-txt-transform example/siglus-txt-transform/json example/siglus-txt-transform/txt-out
# 该命令会将example/siglus-txt-transform/json目录下的所有json文件转换为txt文件，并输出到example/siglus-txt-transform/txt-out目录下，转换过程中会从example/siglus-txt-transform目录下寻找同名txt文件以提取标识符
```

`j2t` 支持可选参数 `--space`，会在译文每个字符之间插入空格：

```bash
luajit siglus-txt-transform.lua j2t example/siglus-txt-transform/01.ss.txt example/siglus-txt-transform/01.ss.json out.txt --space
```
