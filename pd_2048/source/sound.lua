---@diagnostic disable

import "CoreLibs/object"

local pd <const> = playdate

-- BGMのテーブル.
local bgmTable = {
	"01_minimal",
	"02_chillstep1",
	"03_chillstep2",
	"10_mystictribal1",
	"11_mystictribal2",
	"12_electronica1",
	"13_electronica2",
	"14_organic1",
	"15_organic2",
	"16_tribal1",
	"17_tribal2",
	"50_darktribal1",
	"51_darktribal2",
	"52_techno1",
	"53_techno2",
	"54_minimal",
	"55_minimal2",
	"56_industrial1",
	"57_industrial2",
	"58_acid1",
	"59_acid2",
	"70_hardtrance1",
	"71_hardtrance2",
	"72_hardtribal",
	"73_hardtribal",
	"74_cyber",
	"75_minimal",
	"76_minimal",
}

-- メニュー用のBGMのテーブル.
local bgmMenuTable = {
	"01_minimal",
	"02_chillstep1",
	"03_chillstep2",
}

-- 通常BGMのテーブル.
local bgmNormalTable = {
	"10_mystictribal1",
	"11_mystictribal2",
	"12_electronica1",
	"13_electronica2",
	"14_organic1",
	"15_organic2",
	"16_tribal1",
	"17_tribal2",
}
-- 危機BGMのテーブル.
local bgmCrisisTable = {
	"50_darktribal1",
	"51_darktribal2",
	"52_techno1",
	"53_techno2",
	"54_minimal",
	"55_minimal2",
	"56_industrial1",
	"57_industrial2",
	"58_acid1",
	"59_acid2",
}
-- Ambientアレンジのテーブル.
local bgmAmbientTable = {
	"70_hardtrance1",
	"71_hardtrance2",
	"72_hardtribal",
	"73_hardtribal",
	"74_cyber",
	"75_minimal",
	"76_minimal",
}

-- SEテーブル.
local seTable = {
	-- 効果音.
	"pi",
	"fall",
	"fixed",
	"merge",
	"rotate",
	"hold",
	"rewind",
	"rewind_button",
	"decide",
	"error",
	"complete",
	"gameover",
	"combo1",
	"combo2",
	"combo3",
	"countdown",
	-- ボイス.
	"voice_getready",
	"voice_complete",
}

class('Sound').extends()

-- BGMランダム再生モード (グローバル定義).
BGMRandomMode = {
	ALL = 0, -- 全曲ランダム.
	NOMAL = 1, -- 通常BGMのみランダム.
	CRISIS = 2, -- 危機BGMのみランダム.
	MENU = 3, -- メニューBGMのみランダム.
}

-- SEをロードする.
function Sound:init()
	Sound.super.init(self)

	-- BGM.
	self.player = nil
	self.currentBgmIndex = nil
	self.bgmRandomMode = BGMRandomMode.MENU -- デフォルトはメニューBGM.
	self.bgmRandomCount = 0 -- ランダム再生回数.
	self.isChangingBgm = false

	-- SEは常駐.
	self.pool = {}
	for _, soundName in ipairs(seTable) do
		-- print("Sound:init() - loading SE: " .. soundName)
		self.pool[soundName] = pd.sound.sampleplayer.new("sounds/se/" .. soundName)
	end
end

-- BGMを再生する.
function Sound:play_bgm(bgmIndex, isStop)
	-- print("Sound:play_bgm() - requested BGM index: " .. tostring(bgmIndex) .. ", isStop: " .. tostring(isStop))
	-- 再生中のBGMを停止して新しく再生するかどうか.
	local bStop = isStop
	if bStop == nil then
		bStop = true
	end
	if bStop == false and self:isPlaying() then
		-- 再生中のBGMがある場合は何もしない.
		return
	end
	local index = bgmIndex
	if index == nil or index < 0 then
		-- ランダムで抽選する.
		index = self:randomBgmIndex()
	end

	if bgmTable[index] then		
		local bgmName = bgmTable[index]
		-- print("Sound:play_bgm() - playing BGM: " .. bgmName)
		-- 再生していたら停止.
		if self.player ~= nil then
			self.isChangingBgm = true
			self.player:setFinishCallback(nil)
			self.player:stop()
			self.isChangingBgm = false
		end
		self.player = pd.sound.fileplayer.new("sounds/bgm/" .. bgmName)
		if self.player ~= nil then
			self.player:setFinishCallback(function(player, sound)
				sound:onBgmFinished(player)
			end, self)
			self.player:setVolume(1.0)
			self.player:play()
			self.currentBgmIndex = index
		else
			print("Sound:play_bgm() - Failed to create player for BGM: " .. bgmName)
		end
	else
		print("Sound:play_bgm() - BGM index " .. index .. " not found.")
	end
end

-- BGMを停止する.
-- fadeSecondsに正の値を指定すると、その秒数でフェードアウトしてから停止する.
function Sound:stop_bgm(fadeSeconds)
	if self.player == nil then
		return
	end

	local player = self.player
	local seconds = fadeSeconds or 0
	self.isChangingBgm = true
	player:setFinishCallback(nil)

	if seconds > 0 and player:isPlaying() then
		player:setVolume(0, 0, seconds, function(finishedPlayer, sound)
			if finishedPlayer ~= sound.player then
				return
			end

			finishedPlayer:stop()
			sound.player = nil
			sound.isChangingBgm = false
		end, self)
	else
		player:stop()
		if player == self.player then
			self.player = nil
		end
		self.isChangingBgm = false
	end
end

-- BGMランダム再生モードを設定する.
function Sound:setBgmRandomMode(mode)
	if self.bgmRandomMode == mode then
		-- すでに同じモードを設定していたら変更しない.
		return
	end
	print("Sound:setBgmRandomMode() - changing BGM random mode to: " .. tostring(mode))
	self.bgmRandomMode = mode
	self.bgmRandomCount = 0 -- ランダム再生回数をリセット.
end

function Sound:playMenuBgm()
	self:setBgmRandomMode(BGMRandomMode.MENU)
	self:play_bgm(-1, false)
end

function Sound:playGameBgm()
	self:setBgmRandomMode(BGMRandomMode.NOMAL)
	self:play_bgm(-1, false)
end

function Sound:onBgmFinished(player)
	if self.isChangingBgm or player ~= self.player then
		return
	end

	self:play_bgm(-1, true)
end

function Sound:randomBgmIndexFromMode()
	-- ランダム再生モードに応じてBGMの抽選対象を決定する.
	local targetTable = bgmTable
	if self.bgmRandomMode == BGMRandomMode.NOMAL then
		targetTable = bgmNormalTable -- 通常BGMのみを対象とする.
	elseif self.bgmRandomMode == BGMRandomMode.CRISIS then
		targetTable = bgmCrisisTable -- 危機BGMのみを対象とする.
		if self.bgmRandomCount%3 == 2 then
			targetTable = bgmAmbientTable -- 3回に1回はAmbientアレンジを対象とする.
		end
	elseif self.bgmRandomMode == BGMRandomMode.MENU then
		targetTable = bgmMenuTable -- メニューBGMのみを対象とする.
	end

	local index = math.random(1, #targetTable)
	local bgmName = targetTable[index]
	for i, name in ipairs(bgmTable) do
		if name == bgmName then
			index = i
			break
		end
	end
	return index
end

function Sound:randomBgmIndex()
	if #bgmTable <= 1 then
		return 1
	end

	local index = self:randomBgmIndexFromMode()
	-- 同じBGMが連続しないようにする.
	if self.currentBgmIndex ~= nil then
		local cntLoop = 10 -- ループ回数の上限を設定.
		while index == self.currentBgmIndex do
			-- 重複しているので再抽選.
			index = self:randomBgmIndexFromMode()
			cntLoop -= 1
			if cntLoop <= 0 then
				-- ループ回数の上限に達した場合は強制的に終了する.
				break
			end
		end
	end
	-- ランダム再生回数をカウントする.
	self.bgmRandomCount += 1
	return index
end

-- BGMが再生中かどうか.
function Sound:isPlaying()
	if self.player ~= nil then
		return self.player:isPlaying()
	end
	return false
end

-- SEを再生する.
function Sound:play_se(soundName)
	if self.pool ~= nil and self.pool[soundName] ~= nil then
		-- print("Sound:play_se() - playing SE: " .. soundName)
		self.pool[soundName]:play()
	else
		print("Sound:play_se() - SE '" .. soundName .. "' not found.")
	end
end

-- SEを停止する.
function Sound:stop_se(soundName)
	if self.pool ~= nil and self.pool[soundName] ~= nil then
		print("Sound:stop_se() - stopping SE: " .. soundName)
		self.pool[soundName]:stop()
	else
		print("Sound:stop_se() - SE '" .. soundName .. "' not found.")
	end
end
