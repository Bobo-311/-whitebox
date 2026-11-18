extends ColorRect

# ==========================================
# 《眠境 RE:COLOR》主選單管理系統
# 第一階段：基礎畫面與視窗比例管理
# ==========================================

# 主選單的基準設計解析度
# 所有首頁素材皆按照此尺寸進行排版
const DESIGN_SIZE: Vector2 = Vector2(1600, 900)

# 取得主選單畫布節點
@onready var design: Control = $Design


# ==========================================
# 初始化主選單
# ==========================================

func _ready() -> void:

	# 讓根節點填滿整個遊戲視窗
	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	# 設定畫布的基準尺寸
	design.size = DESIGN_SIZE

	# 使用線性過濾，讓高解析度圖片更加平滑
	# 不影響其他遊戲場景的像素畫風
	design.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR
	)

	# 當遊戲視窗大小改變時
	# 自動重新計算畫面的顯示比例
	resized.connect(_resize_menu)

	# 首次進入主選單時進行畫面調整
	_resize_menu()


# ==========================================
# 視窗等比例縮放
# 避免背景、Logo 及未來的按鈕變形
# ==========================================

func _resize_menu() -> void:

	# 防止視窗尚未初始化時發生錯誤
	if size.x <= 0.0 or size.y <= 0.0:
		return

	# 分別計算視窗的水平與垂直比例
	var scale_x: float = size.x / DESIGN_SIZE.x
	var scale_y: float = size.y / DESIGN_SIZE.y

	# 採用較小的比例，確保完整畫面可以顯示
	var scale_factor: float = minf(scale_x, scale_y)

	# 等比例縮放主選單畫布
	design.scale = Vector2.ONE * scale_factor

	# 將畫布置中
	design.position = (
		size - DESIGN_SIZE * scale_factor
	) * 0.5
