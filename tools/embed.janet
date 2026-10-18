# tools/embed.janet —— 生成静态嵌入产物（REQ-38：amalgamated 静态嵌入）
#
# 用法：janet tools/embed.janet <manifest> <outdir> [--core-only]
# 产物：<outdir>/rb-bundle.janet  拼接后的内核源码（测试用）
#       <outdir>/rb_bundle.c/.h   C 字节数组（随宿主一起编译）

(def raw-args (dyn :args))
(def flag-args (filter (fn [a] (string/has-prefix? "--" a)) raw-args))
# janet 的 (dyn :args) = [脚本路径, 参数...]
(def pos-args (slice (filter (fn [a] (not (string/has-prefix? "--" a))) raw-args) 1))
(def manifest (get pos-args 0))
(def outdir (get pos-args 1))
(def core-only? (truthy? (some (fn [a] (= a "--core-only")) flag-args)))

(when (or (nil? manifest) (nil? outdir))
  (eprintf "用法：janet tools/embed.janet <manifest> <outdir> [--core-only]\n")
  (os/exit 2))

(defn read-manifest
  [path]
  (def files @[])
  (each line (string/split "\n" (slurp path))
    (def t (string/trim line))
    (when (and (not (empty? t)) (not (string/has-prefix? "#" t)))
      (when (or (not core-only?) (not (string/has-prefix? "cap/" t)))
        (array/push files t))))
  files)

(def files (read-manifest manifest))

(def buf @"")
(buffer/push-string buf "### ravel breve 内核 bundle —— 由 tools/embed.janet 生成，请勿手改\n")
(each f files
  (buffer/push-string buf (string "\n### " f "\n"))
  (buffer/push-string buf (slurp f)))
(def bundle (string buf))

(defn c-array
  [name bytes]
  (def b @"")
  (buffer/push-string b (string "const unsigned char " name "[] = {\n"))
  (var col 0)
  (each by bytes
    (buffer/push-string b (string/format "0x%02x," by))
    (++ col)
    (when (= col 16)
      (buffer/push-string b "\n")
      (set col 0)))
  (buffer/push-string b "\n};\n")
  (string b))

(def header
  (string "/* 由 tools/embed.janet 生成，请勿手改 */\n"
          "#ifndef RB_BUNDLE_H\n#define RB_BUNDLE_H\n"
          "extern const unsigned char rb_bundle[];\n"
          "extern const unsigned int rb_bundle_len;\n"
          "#endif\n"))

(def c-src
  (string "/* 由 tools/embed.janet 生成，请勿手改 */\n"
          "#include \"rb_bundle.h\"\n"
          (c-array "rb_bundle" bundle)
          "const unsigned int rb_bundle_len = " (length bundle) ";\n"))

(spit (string outdir "/rb-bundle.janet") bundle)
(spit (string outdir "/rb_bundle.c") c-src)
(spit (string outdir "/rb_bundle.h") header)

(printf "embed: %d 个文件, %d 字节%s\n"
        (length files) (length bundle)
        (if core-only? "（仅核心，已剔除 cap/）" ""))
