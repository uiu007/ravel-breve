# cap/preset.janet —— 能力层：provider 配置预设（v1.0k 的 REQ-62 / REQ-63）
#
# 预设 = 一个 JSON 对象，键就是工作区配置的白名单键（rb/config-keys）：
#
#   { "provider": "opencode", "model": "deepseek-v4.1-flash", "max-tokens": 1024 }
#
# 为什么是「文件 + 名字」而不是又一套配置语法：D-54 已经把 provider 配置放进工作区，
# 缺的只是**一次写多行**与**存下来**。于是：
#
#   llm-import "opencode-go"      # 名字 → presets/opencode-go.json（也可给路径）
#   llm-export ".ravel.json"      # 把当前**生效**配置写回去
#
# 三条不变式（都来自既有决策，不是新规矩）：
#   ① 只写工作区配置的白名单键；`key` 之类一律 31（D-54：密钥不进工作区）。
#   ② 幂等：导入只覆盖预设里出现的键，其余保持原样（可以叠加几份预设）。
#   ③ 密钥永不落盘：导出时若 `headers` 里出现疑似密钥的头名 → 31，宁可导不出去。
#
# 启动装载（REQ-63）也在这里：`cap/preset-startup` 由 rb/eval.janet 的 `rb/new-env`
# 经间接层调用（D-29），顺序是 用户配置文件 → RB_PRESET → `--preset`（后者优先）。

(def cap/preset-dir "presets")

(def cap/preset-headers-secret-key?
  "疑似密钥的请求头名（导出时拒绝写盘；D-54 的延伸）。"
  (fn [k]
    (def s (string/ascii-lower (string k)))
    (or (string/find "authorization" s)
        (string/find "api-key" s)
        (string/find "apikey" s)
        (string/find "secret" s)
        (string/find "token" s)
        (string/find "cookie" s))))

(defn cap/preset-cap
  "取一个能力；没有就报 60（REQ-37：核心/能力层的边界不在预设这里破）。"
  [k what]
  (def f (rb/cap-get k))
  (when (nil? f)
    (rb/raise (rb/exit-table :orchestration-base)
              (string what "（REQ-37：核心不含文件/JSON 实现）")))
  f)

(defn cap/preset-path
  "名字或路径 → 文件路径。带 `/` 或以 `.json` 结尾就当路径；否则 `presets/<名字>.json`。"
  [x]
  (cond
    (not (string? x))
    (rb/raise (rb/exit-table :runtime-type)
              (string "预设需要名字或路径字符串，得到 " (type x)))
    (empty? (string/trim x))
    (rb/raise (rb/exit-table :runtime-type) "预设名字不能为空")
    (or (string/find "/" x)
        (string/has-suffix? ".json" x)) x
    (string cap/preset-dir "/" x ".json")))

(defn cap/preset-check
  "校验预设表 → 归一后的表（键必须是字符串、值不许是 key）。坏 → 31。"
  [tbl path]
  (when (not (dictionary? tbl))
    (rb/raise (rb/exit-table :runtime-type)
              (string "预设必须是 JSON 对象：" path)))
  (def out @{})
  (eachp [k v] tbl
    (def key (string k))
    (when (= key "key")
      (rb/raise (rb/exit-table :orchestration-base)
                (string "预设里不能有密钥（D-54）：" path)))
    # 白名单校验复用核心（rb/config-check）：预设不新开一套规则
    (rb/config-check key)
    (when (not (nil? v)) (put out key v)))
  out)

(defn cap/preset-parse
  "JSON 文本 → 预设表。"
  [text path]
  (def dec (cap/preset-cap :json/decode "读取预设需要 :json/decode"))
  (def p (protect (dec text)))
  (when (not (get p 0))
    (rb/raise (rb/exit-table :runtime-type)
              (string "预设不是合法 JSON：" path "（" (rb/error-msg (get p 1)) "）")))
  (cap/preset-check (get p 1) path))

(defn cap/preset-slurp
  "直接读文件（不走沙箱）：**只给启动装载用**——那时还没有任何方言程序在跑，
   而用户配置天然在沙箱外（`~/.config/ravel/config.json`），与密钥文件同一个道理。"
  [path]
  (def p (protect (slurp path)))
  (if (get p 0)
    (string (get p 1))
    (rb/raise (rb/exit-table :io-read)
              (string "预设文件不存在或无权限：" path))))

(defn cap/preset-read
  "读一个预设文件 → 表。方言里的 `llm-import` 走这里：经 `:fs/read`，**受沙箱约束**（REQ-53）。"
  [path]
  (def read (cap/preset-cap :fs/read "读取预设需要能力 :fs/read（cap/fs）"))
  (def text (read path))
  (when (nil? text)
    (rb/raise (rb/exit-table :io-read)
              (string "预设文件不存在或无权限（沙箱只允许当前目录，REQ-53）：" path)))
  (cap/preset-parse text path))

(defn cap/preset-apply
  "把预设写进**工作区配置**（只覆盖出现的键），返回生效后的配置表。"
  [tbl]
  (eachp [k v] tbl (rb/config-set k v))
  (rb/config))

(defn cap/preset-import
  "`llm-import` 的实现（沙箱内）：名字或路径 → 写进工作区配置 → 返回配置表。"
  [name-or-path]
  (cap/preset-apply (cap/preset-read (cap/preset-path name-or-path))))

(defn cap/preset-import-raw
  "启动装载用（沙箱外直读）：名字或路径 → 写进工作区配置。"
  [name-or-path]
  (cap/preset-apply
    (cap/preset-parse (cap/preset-slurp (cap/preset-path name-or-path))
                      (cap/preset-path name-or-path))))

(defn cap/preset-export
  "`llm-export` 的实现：**工作区显式配置**（`llm` 那张表）→ 预设文件 → 写入项数。

   只导显式的、不导环境变量推出来的值：预设要能跨机器用（`RB_OC_BASE` 之类是这台机器的
   事），导出的东西必须能原样再 `llm-import` 回来。"
  [path]
  (when (not (string? path))
    (rb/raise (rb/exit-table :runtime-type)
              (string "llm-export 需要一个路径字符串，得到 " (type path))))
  (def write (cap/preset-cap :fs/write "导出预设需要能力 :fs/write（cap/fs）"))
  (def enc (cap/preset-cap :json/encode "导出预设需要 :json/encode"))
  (def cfg (rb/config))
  (def out @{})
  (each k rb/config-keys
    (def v (get cfg k))
    (when (not (nil? v)) (put out k v)))
  # 密钥永不落盘：`headers` 里带 Authorization / api-key 之类就报错，让用户先删
  (def h (get out "headers"))
  (when (dictionary? h)
    (eachp [k _] h
      (when (cap/preset-headers-secret-key? k)
        (rb/raise (rb/exit-table :orchestration-base)
                  (string "预设不写密钥（D-54）：headers 里有 " k
                          "；先 llm-set nil \"headers\" 或改走环境变量再导出")))))
  # 写盘失败/越界写一律 41（与 `write` 词同一条映射，REQ-53）
  (def w (protect (write (string (enc out) "\n") path)))
  (when (not (get w 0))
    (rb/raise (rb/exit-table :io-write)
              (string "预设写入失败：" path "（" (rb/error-msg (get w 1)) "）")))
  (length (pairs out)))

# ---- 启动装载（REQ-63）--------------------------------------------------

(defn cap/preset-user-path
  "用户配置文件路径：`RB_CONFIG` > `$XDG_CONFIG_HOME/ravel/config.json` > `~/.config/ravel/config.json`。
   `RB_CONFIG` 为空串或 `-` = 显式关闭（测试用，见 Makefile）。"
  []
  (def raw (os/getenv "RB_CONFIG"))
  (cond
    (and raw (or (empty? raw) (= raw "-"))) nil
    raw raw
    (do
      (def xdg (os/getenv "XDG_CONFIG_HOME"))
      (def base (if (and xdg (not (empty? xdg)))
                  xdg
                  (string (or (os/getenv "HOME") "") "/.config")))
      (string base "/ravel/config.json"))))

(defn cap/preset-startup
  "`rb/new-env` 调：用户配置 → `RB_PRESET`（逗号）→ `rb/config-presets`（`--preset`，按序）。
   返回装载的预设个数。全部失败都抛（配置错了宁可不启动，也不要静默跑在别的模型上）。"
  [_env]
  (var n 0)
  (def user (cap/preset-user-path))
  (when (and user (os/stat user))
    # 可见：用了哪份配置文件要打在诊断通道上（不是黑箱）
    (eprintf "ravel: 已装载配置 %s\n" user)
    (cap/preset-import-raw user)
    (set n (inc n)))
  (def env-list (os/getenv "RB_PRESET"))
  (when (and env-list (not (empty? (string/trim env-list))))
    (each piece (string/split "," env-list)
      (def nm (string/trim piece))
      (when (not (empty? nm))
        (cap/preset-import-raw nm)
        (set n (inc n)))))
  (each nm rb/config-presets
    (cap/preset-import-raw nm)
    (set n (inc n)))
  n)

# 间接层接线（D-29）：rb/eval.janet 的 `rb/new-env` 里调用
(set rb/config-startup cap/preset-startup)

(rb/cap-put :llm/import cap/preset-import)
(rb/cap-put :llm/export cap/preset-export)
