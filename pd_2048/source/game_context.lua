---@diagnostic disable
--[[
	GameContext.lua

	GameContextクラスは、ゲーム全体の状態を管理するクラスです。(シングルトンの管理)
	各種の共有オブジェクトを保持し、ゲームの初期化や状態管理を行います。
--]]
import "CoreLibs/object"
import "sound"

local gfx <const> = playdate.graphics

---ゲームコンテキスト.
---@class GameContext : Object
class("GameContext").extends()

GameContext.instance = nil

-- シングルトンインスタンスを取得.
function GameContext.getInstance()
	if GameContext.instance == nil then
		GameContext.instance = GameContext()
	end
	return GameContext.instance
end

-- 初期化.
function GameContext:init()
	-- ここシングルトンとして保持したいオブジェクトの変数を保持.
	self.sound = Sound()
	print("GameContext:init() - Sound instance created.")
	-- フォント読み込み.
	self.font = nil -- フォント差し替え用.
	--self.font = playdate.graphics.font.new("fonts/font12x12")
	--print(self.font, "GameContext:init() - Font loaded.")
	--playdate.graphics.setFont(self.font)
end

-- 破棄.
function GameContext:destroy()
	-- ここに破棄処理を記述する.
	self.sound = nil
	self.font = nil
end

-- ゲームで使う共有オブジェクトを一度だけ初期化する.
function GameContext:setup()
	-- ここでインスタンスを生成.
end
