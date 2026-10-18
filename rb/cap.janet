# rb/cap.janet —— 能力层注册表（§4.11 / REQ-37）
#
# 核心**不认识**具体能力（JSON / HTTP / 文件 / 加密…），只认识这张注册表。
# 能力实现放在 cap/ 下，装载时自我注册；核心用名字取用（缺失即降级/报错）。
# 这样「剔除 cap/ 后核心仍可装载并完成主脊」是可验证的（附录 D）。

(def rb/cap @{})

(defn rb/cap-put
  "注册一个能力（由 cap/ 下的文件在装载时调用）。"
  [k v]
  (put rb/cap k v)
  v)

(defn rb/cap-get
  "取一个能力；未注册返回 nil。"
  [k]
  (get rb/cap k))

(defn rb/cap?
  [k]
  (not (nil? (get rb/cap k))))
