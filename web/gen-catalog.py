#!/usr/bin/env python3
"""web/gen-catalog.py —— 从规格的附录 A 生成前端的词表（words.json）。

为什么从规格里抠、而不是手写一份：
    手写的词表会跟规格漂移，而"可用的命令一览"最怕漂移。附录 A 是唯一的词表出处，
    所以这里只做机械提取（表格行 + 反引号名），再叠一层"补注"（L0 与算术等
    规格里写成散文/裸名的那几层），补注只在没有更权威的描述时生效。

用法:
    python3 web/gen-catalog.py                       # 写 web/words.json
    python3 web/gen-catalog.py --spec path --out x   # 指定出入

产物形状:
    {"version": "1.0s", "spec": "ravel-breve-spec-v1.0s.md",
     "groups": [{"layer": "L1", "title": "序列、文本与连接（多态）",
                 "words": [{"name": ",", "effect": "X Y -- XY", "desc": "…", "arity": 2}]}]}
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# ---- 补注：规格里没有"表格行"的那几层 -------------------------------------
# 只补 name/effect/desc；有表格行时表格行优先（见 merge 逻辑）。
SUPPLEMENT = {
    "L0": ("核心栈 / 组合子", [
        ("dup", "a -- a a", "复制栈顶"),
        ("pop", "a --", "丢弃栈顶"),
        ("swap", "a b -- b a", "交换栈顶两项"),
        ("rot", "a b c -- b c a", "三旋：最深的一项转到栈顶"),
        ("-rot", "a b c -- c a b", "逆三旋：栈顶转到最深处"),
        ("keep", "a [q] -- a r", "保留 a 再对 a 求 q，得 a 与结果"),
        ("dip", "a [q] -- r a", "把 a 挪开，对下面求 q，再把 a 放回栈顶"),
        ("apply", "a [q] -- r", "对 a 求 q（= 调用）"),
        ("call", "a [q] -- r", "apply 的同义"),
    ]),
    "L1b": ("布尔 / 比较 / 算术", [
        ("=", "a b -- Bool", "相等"),
        ("!=", "a b -- Bool", "不等"),
        ("<", "a b -- Bool", "小于（`< 5 3` 读作 5 与 3）"),
        (">", "a b -- Bool", "大于"),
        ("<=", "a b -- Bool", "小于等于"),
        (">=", "a b -- Bool", "大于等于"),
        ("not", "Bool -- Bool", "取反"),
        ("and", "Bool Bool -- Bool", "与"),
        ("or", "Bool Bool -- Bool", "或"),
        ("+", "a b -- n", "加"),
        ("-", "a b -- n", "减"),
        ("*", "a b -- n", "乘"),
        ("/", "a b -- n", "除"),
        ("mod", "a b -- n", "取余"),
        ("abs", "n -- n", "绝对值"),
        ("min", "a b -- x", "较小者"),
        ("max", "a b -- x", "较大者"),
        ("sum", "seq -- n", "求和"),
    ]),
    "L1c": ("字符串工具", [
        ("trim", "String -- String", "去首尾空白"),
        ("replace", "From To String -- String", "替换全部"),
        ("contains", "Sub String -- Bool", "是否包含"),
        ("starts-with", "Prefix String -- Bool", "前缀判断"),
        ("ends-with", "Suffix String -- Bool", "后缀判断"),
        ("lines", "String -- seq", "按行拆"),
        ("words", "String -- seq", "按空白拆词"),
    ]),
    "L1d": ("类型转换", [
        ("to-string", "x -- String", "转文本"),
        ("to-int", "x -- Int", "转整数"),
    ]),
    "L5": ("控制流", [
        ("if", "cond [then] [else] -- x", "条件分支（也可用条件已在栈上的写法）"),
        ("when", "cond [then] -- x", "条件为真时求引号"),
        ("unless", "cond [then] -- x", "条件为假时求引号"),
        ("loop", "N [body] -- x", "循环 N 次"),
        ("while", "[cond] [body] -- x", "条件为真则循环"),
        ("try", "[body] [catch] -- x", "异常处理"),
        ("recover", "[body] [handler] -- x", "失败回退"),
    ]),
    "L5b": ("错误 / 调试 / 环境", [
        ("fail", "x --", "抛出失败（退出码 60）"),
        ("assert", "Bool Msg --", "断言，失败即 60"),
        ("depth", "-- Int", "数据栈深度"),
        ("dump", "--", "打印工作区概要"),
        ("now", "-- Int", "当前时间（毫秒）"),
        ("env", "Key -- Value", "读环境变量"),
    ]),
    "L6": ("元词表", [
        ("doc", "Name -- String", "看一个词的文档"),
        ("see", "Name --", "看一个词的实现"),
    ]),
    "L8": ("钩子与 agent 必备", [
        ("@on", "Event [quot] --", "注册钩子"),
        ("@off", "Event --", "注销该事件上的钩子"),
        ("deftool", "Name Desc [quot] --", "登记一个工具"),
        ("invoke", "Name Json -- Json", "直接调用工具（不经模型、不走审批）"),
        ("resend", "Agent|Stream -- Stream", "按现有会话重发"),
        ("stop", "Stream --", "停止该流"),
        ("cancel", "-- Int", "停掉所有还开着的流"),
        ("drain", "--", "把挂着的流跑完"),
        ("next", "--", "推进一次事件循环"),
    ]),
    "L9": ("前端订阅", [
        ("watch", "Agent -- Stream", "主屏渲染源（只读视图流）"),
    ]),
    "L10": ("处理流程（模式）", [
        ("mode", "Name|Mode --", "装模式"),
        ("modes", "-- list String", "预制模式名"),
        ("mode-of", "-- Mode", "导出当前工作区的处理流程"),
        ("mode-name", "Mode -- String", "模式名"),
        ("mode-prompt", "Mode -- String|nil", "模式的系统提示"),
        ("mode-tools", "Mode -- list String", "模式声明的工具名"),
        ("flag", "Key -- Bool", "读开关"),
        ("flag-set", "Value Key --", "写开关"),
        ("enter-plan", "--", "进 plan 模式"),
        ("exit-plan", "--", "退出 plan 模式"),
    ]),
}

BAD_NAMES = {"?", "…", "x", "X"}


def find_spec(explicit=None):
    if explicit:
        return explicit
    best = None
    for fn in sorted(os.listdir(ROOT)):
        m = re.match(r"ravel-breve-spec-v(\d+)\.(\d+)([a-z]?)\.md$", fn)
        if not m:
            continue
        key = (int(m.group(1)), int(m.group(2)), m.group(3))
        if best is None or key > best[0]:
            best = (key, fn)
    if best is None:
        raise SystemExit("找不到 ravel-breve-spec-v*.md")
    return os.path.join(ROOT, best[1])


def appendix_a(text):
    start = text.index("## 附录 A")
    end = text.find("\n## 附录 ", start + 10)
    return text[start: end if end > 0 else len(text)]


NAMES_RE = re.compile(r"`([^`]+)`")


def split_names(cell):
    """`a` / `b`、`Role` `Content` 这样的名字格 → 名字列表。"""
    names = []
    for raw in NAMES_RE.findall(cell):
        raw = raw.strip()
        if not raw or any(c in raw for c in "{}…"):
            continue
        if " " in raw:  # `Agent|Stream` 之类已在上面拆过；带空格的跳过
            continue
        names.append(raw)
    # `a` / `b` 这种斜杠分隔：NAMES_RE 已各自取出，无需再拆
    return names


def infer_arity(effect):
    if not effect or "--" not in effect:
        return 0
    left = effect.split("--", 1)[0].strip()
    if not left:
        return 0
    n = 0
    depth = 0
    for tok in left.split():
        if depth == 0 and tok.startswith("["):
            n += 1
        if depth == 0 and not tok.startswith("[") and not tok.endswith("]"):
            n += 1
        depth += tok.count("[") - tok.count("]")
    return max(0, min(n, 6))


def parse(section):
    groups = []
    cur = None
    for raw in section.splitlines():
        line = raw.rstrip()
        m = re.match(r"^### (L[\w]*)\s*(.*)$", line)
        if m:
            cur = {"layer": m.group(1), "title": m.group(2).strip(), "rows": []}
            groups.append(cur)
            continue
        if cur is None:
            continue
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) < 3:
                continue
            if set(cells[0]) <= set("-: "):  # 分隔行
                continue
            name_cell = cells[0]
            if name_cell.startswith("词"):
                continue
            if name_cell.startswith("~~"):  # 已移出词表
                continue
            names = split_names(name_cell)
            if not names:
                continue
            effect = cells[1].replace("`", "").strip()
            desc = cells[2].replace("**", "").replace("`", "").strip()
            # `a` / `b` 两个名字共享 effect 时，effect 里也有 `/`：按顺序对位
            effs = [e.strip() for e in effect.split(" / ")]
            for i, n in enumerate(names):
                e = effs[i] if len(effs) == len(names) else effect
                cur["rows"].append({"name": n, "effect": e, "desc": desc})
            continue
        # 裸名行：整行几乎都是反引号里的名字（L1b/L1c/L5 …），允许一个短标签前缀
        # （`- 事件：`@Start` …`）。判定用「把代码跨度全抠掉之后还剩多少散文」，
        # 这样 `- 递归：… 深度看 `depth`，超限按 60` 这种散文句不会被当成名字行。
        if line.startswith("`") or line.startswith("- "):
            names = [n for n in NAMES_RE.findall(line) if " " not in n and n not in ("…",)]
            if not names:
                continue
            rest = NAMES_RE.sub("", line).strip()
            if rest.startswith("- "):
                rest = rest[2:].strip()
            rest = re.sub(r"^[*_]{0,4}[^：:]{1,14}[：:]", "", rest).strip()
            if len(re.sub(r"[\s,，、/·和与即or]", "", rest)) > 2:
                continue
            for n in names:
                if n in BAD_NAMES:
                    continue
                if not re.match(r"^[@A-Za-z0-9_+\-*/<>=!,.%?&|~^\[\]]+$", n):
                    continue
                cur["rows"].append({"name": n, "effect": "", "desc": ""})
    return groups


def build(spec_path):
    text = open(spec_path, encoding="utf-8").read()
    groups = parse(appendix_a(text))
    spec_name = os.path.basename(spec_path)
    m = re.search(r"v(\d+\.\d+[a-z]?)\.md$", spec_name)
    version = m.group(1) if m else "?"

    # 叠补注：没有行就整层新建；有行则只补缺失的名字
    by_layer = {g["layer"]: g for g in groups}
    for layer, (title, rows) in SUPPLEMENT.items():
        g = by_layer.get(layer)
        if g is None:
            g = {"layer": layer, "title": title, "rows": []}
            groups.append(g)
            by_layer[layer] = g
        have = {r["name"] for r in g["rows"]}
        for name, effect, desc in rows:
            if name not in have:
                g["rows"].append({"name": name, "effect": effect, "desc": desc})
    # 补注也要给"有名字但没效应"的行填上效应
    sup = {n: (e, d) for _, (_, rows) in SUPPLEMENT.items() for n, e, d in rows}
    for g in groups:
        for r in g["rows"]:
            if not r["effect"] and r["name"] in sup:
                r["effect"], r["desc"] = sup[r["name"]]

    order = ["L0", "L1", "L1b", "L1c", "L1d", "L2", "L3", "L4", "L5", "L5b",
             "L6", "L7", "L8", "L9", "L9b", "L10"]
    groups.sort(key=lambda g: order.index(g["layer"]) if g["layer"] in order else 99)

    out, seen = [], set()
    for g in groups:
        words = []
        for r in g["rows"]:
            name = r["name"]
            if name in seen:
                continue
            seen.add(name)
            words.append({
                "name": name,
                "effect": r["effect"],
                "desc": r["desc"],
                "arity": infer_arity(r["effect"]),
            })
        if words:
            out.append({"layer": g["layer"], "title": g["title"], "words": words})
    return {
        "version": version,
        "spec": spec_name,
        "generated_by": "web/gen-catalog.py",
        "groups": out,
    }


def main(argv):
    spec = None
    out = os.path.join(HERE, "words.json")
    it = iter(argv[1:])
    for a in it:
        if a == "--spec":
            spec = next(it)
        elif a == "--out":
            out = next(it)
        else:
            raise SystemExit(__doc__)
    data = build(find_spec(spec))
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    n = sum(len(g["words"]) for g in data["groups"])
    print(f"{out}: {n} 个词 / {len(data['groups'])} 层（来源 {data['spec']}）")


if __name__ == "__main__":
    main(sys.argv)
