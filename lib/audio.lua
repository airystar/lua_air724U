--- 模块功能：音频播放.
-- 支持MP3、amr文件播放；
-- 支持本地TTS播放、通话中TTS播放到对端（需要使用支持TTS功能的core软件）
-- @module audio
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.3.19

require "common"
require "misc"
require "utils"
module(..., package.seeall)

local req = ril.request
local stopCbFnc
--tts速度，默认50
local ttsSpeed = 50
--喇叭音量和mic音量等级
local sVolume,sMicVolume = 4,1
local sCallVolume = 4



--音频播放的协程ID
local taskID


--播放和停止请求队列，用于存储通过调用audio.play和audio.stop接口允许播放和停止播放的请求项

--每个播放请求项为table类型，数据结构如下（参考本文件中的play接口注释）
--priority：播放优先级
--type：播放类型
--path：播放音频内容
--vol：播放音量
--cbFnc：播放结束后的回调函数
--dup：是否重复播放
--dupInterval：重复播放的间隔，单位毫秒

--每个停止请求项为table类型，数据结构如下（参考本文件中的stop接口注释）
--type：固定为"STOP"
--cbFnc：停止播放后的回调函数
local audioQueue = {}

--sStrategy：优先级相同时的播放策略，0(表示继续播放正在播放的音频，忽略请求播放的新音频)，1(表示停止正在播放的音频，播放请求播放的新音频)
local sStrategy

local function isTtsStopResultValid()
    return tonumber(string.match(rtos.get_version(),"Luat_V(%d+)_"))>=8
end


local function handleCb(item,result)
    log.info("audio.handleCb",item.cbFnc,result)
    if item.cbFnc then item.cbFnc(result) end
    table.remove(audioQueue,1)
end

local function handlePlayInd(item,key,value)
    log.info("audio.handlePlayInd",key,value)
    --播放结束
    if key=="RESULT" then
        --播放成功
        if value then
            if item.dup then
                if item.dupInterval>0 then
                    log.info("audio.handlePlayInd",item.type,"dup wait LIB_AUDIO_PLAY_IND or timeout",item.dupInterval)
                    local result,reason = sys.waitUntil("LIB_AUDIO_PLAY_IND",item.dupInterval)
                    log.info("audio.handlePlayInd",item.type,"dup wait",reason or "timeout")
                    if result then
                        log.warn("audio.handlePlayInd",item.type,"dup wait error",reason)
                        handleCb(item,reason=="NEW" and 4 or 5)
                    end
                end
            else
                handleCb(item,0)
            end
        --播放失败
        else
            log.warn("audio.handlePlayInd",item.type,"play cnf error")
            handleCb(item,1)
        end
    --新的优先级更高的播放请求
    elseif key=="NEW" then
        log.warn("audio.handlePlayInd",item.type,"priority error")
        handleCb(item,4)
    --主动调用audio.stop
    elseif key=="STOP" then
        log.warn("audio.handlePlayInd",item.type,"stop error",result)
        handleCb(item,5)
    end
end

local ttsEngineInited

local function audioTask()
    while true do
        if #audioQueue==0 then
            log.info("audioTask","wait LIB_AUDIO_PLAY_ENTRY")
            sys.waitUntil("LIB_AUDIO_PLAY_ENTRY")
        end

        local item = audioQueue[1]

        log.info("audioTask",item.type,"#audioQueue",#audioQueue)
        if item.type=="FILE" then
            --队列中有优先级高的请求等待处理
            if #audioQueue>1 then
                log.warn("audioTask",item.type,"priority low")
                local behind = audioQueue[2]
                handleCb(item,behind.type=="STOP" and 5 or 4)
            else
                setVolume(item.vol)
                local result
                if type(item.path)=="table" then
                    result = audiocore.play(unpack(item.path))
                else
                    result = audiocore.play(item.path)
                end
                if result then
                    --等待三种消息（播放结束、主动调用audio.stop、新的优先级更高的播放请求）
                    log.info("audioTask",item.type,"wait LIB_AUDIO_PLAY_IND")
                    local _,key,value = sys.waitUntil("LIB_AUDIO_PLAY_IND")
                    log.info("audioTask",item.type,"recv LIB_AUDIO_PLAY_IND",key,value)

                    audiocore.stop()
                    handlePlayInd(item,key,value)
                else
                    log.warn("audioTask",item.type,"audiocore.play error")
                    audiocore.stop()
                    handleCb(item,1)
                end
            end
        elseif item.type=="TTS" or item.type=="TTSCC" then
            --队列中有优先级高的请求等待处理
            if #audioQueue>1 then
                log.warn("audioTask",item.type,"priority low")
                local behind = audioQueue[2]
                handleCb(item,behind.type=="STOP" and 5 or 4)
            else
                setVolume(item.vol)
                if item.type=="TTS" then
                    if not ttsEngineInited then
                        ttsply.initEngine()
                        ttsEngineInited = true
                    end
                    ttsply.setParm(0,ttsSpeed)
                    --队列中有优先级高的请求等待处理
                    if #audioQueue>1 then
                        log.warn("audioTask",item.type,"priority low1")
                        if isTtsStopResultValid() then
                            if ttsply.stop() then
                                sys.waitUntil("LIB_AUDIO_PLAY_IND",2000)
                            end
                        else
                            ttsply.stop()
                            sys.waitUntil("LIB_AUDIO_PLAY_IND",500)
                        end
                        local behind = audioQueue[2]
                        handleCb(item,behind.type=="STOP" and 5 or 4)
                    else
                        ttsply.play(common.utf8ToGb2312(item.path))

                        --等待三种消息（播放结束、主动调用audio.stop、新的优先级更高的播放请求）
                        log.info("audioTask",item.type,"wait LIB_AUDIO_PLAY_IND")
                        local _,key,value = sys.waitUntil("LIB_AUDIO_PLAY_IND")
                        log.info("audioTask",item.type,"recv LIB_AUDIO_PLAY_IND",key,value)

                        if item.type=="TTS" then
                            if isTtsStopResultValid() then
                                --log.info("tts 1")
                                if ttsply.stop() then
                                    --log.info("tts 2")
                                    sys.waitUntil("LIB_AUDIO_PLAY_IND",2000)
                                end
                                --log.info("tts 3")
                            else
                                ttsply.stop()
                                sys.waitUntil("LIB_AUDIO_PLAY_IND",500)
                            end                            
                        else

                        end

                        handlePlayInd(item,key,value)
                    end
                else

                end
            end
        elseif item.type=="RECORD" then
            --队列中有优先级高的请求等待处理
            if #audioQueue>1 then
                log.warn("audioTask",item.type,"priority low")
                local behind = audioQueue[2]
                handleCb(item,behind.type=="STOP" and 5 or 4)
            else
                setVolume(item.vol)
                f,d=record.getSize()
                req("AT+AUDREC=1,0,2,"..item.path..","..d*1000)

                --等待三种消息（播放结束、主动调用audio.stop、新的优先级更高的播放请求）
                log.info("audioTask",item.type,"wait LIB_AUDIO_PLAY_IND")
                local _,key,value = sys.waitUntil("LIB_AUDIO_PLAY_IND")
                log.info("audioTask",item.type,"recv LIB_AUDIO_PLAY_IND",key,value)

                req("AT+AUDREC=1,0,3,"..item.path..","..d*1000)
                sys.waitUntil("LIB_AUDIO_RECORD_STOP_RESULT")

                handlePlayInd(item,key,value)
            end
        elseif item.type=="STOP" then
            if item.cbFnc then item.cbFnc(0) end
            table.remove(audioQueue,1)
        end
    end
end

--- 播放音频
-- @number priority，音频优先级，数值越大，优先级越高
-- @string type，音频类型，目前仅支持"FILE"、"TTS"、"TTSCC","RECORD"
-- @string path，音频文件路径，跟typ有关
--               typ为"FILE"时：表示音频文件路径
--               typ为"TTS"时：表示要播放的UTF8编码格式的数据
--               typ为"TTSCC"时：表示要播放给通话对端的UTF8编码格式的数据
--               typ为"RECORD"时：表示要播放的录音id
-- @number[opt=4] vol，播放音量，取值范围0到7，0为静音
-- @function[opt=nil] cbFnc，音频播放结束时的回调函数，回调函数的调用形式如下：
-- cbFnc(result)
-- result表示播放结果：
--                   0-播放成功结束；
--                   1-播放出错
--                   2-播放优先级不够，没有播放
--                   3-传入的参数出错，没有播放
--                   4-被新的播放请求中止
--                   5-调用audio.stop接口主动停止
-- @bool[opt=nil] dup，是否循环播放，true循环，false或者nil不循环
-- @number[opt=0] dupInterval，循环播放间隔(单位毫秒)，dup为true时，此值才有意义
-- @return result，bool或者nil类型，同步调用成功返回true，否则返回false
-- @usage audio.play(0,"FILE","/ldata/call.mp3")
-- @usage audio.play(0,"FILE","/ldata/call.mp3",7)
-- @usage audio.play(0,"FILE","/ldata/call.mp3",7,cbFnc)
-- @usage 更多用法参考demo/audio/testAudio.lua
function play(priority,type,path,vol,cbFnc,dup,dupInterval)
    log.info("audio.play",priority,type,path,vol,cbFnc,dup,dupInterval)
    if not taskID then
        taskID = sys.taskInit(audioTask)
    end

    local item = {priority=priority,type=type,path=path,vol=vol or 4,cbFnc=cbFnc,dup=dup,dupInterval=dupInterval or 0}

    if #audioQueue==0 then
        table.insert(audioQueue,item)
        sys.publish("LIB_AUDIO_PLAY_ENTRY")
    else
        local front = audioQueue[#audioQueue]
        if front.type=="STOP" then
            table.insert(audioQueue,item)
        else
            if priority>front.priority or (priority==front.priority and sStrategy==1) then
                table.insert(audioQueue,item)
                sys.publish("LIB_AUDIO_PLAY_IND","NEW")
            else
                log.warn("audio.play","priority error")
                if cbFnc then cbFnc(2) end
            end
        end
    end

    return true
end

--- 停止音频播放
-- @function[opt=nil] cbFnc，停止音频播放的回调函数(停止结果通过此函数通知用户)，回调函数的调用形式为：
--      cbFnc(result)
--      result：number类型
--              0表示停止成功
-- @return nil
-- @usage audio.stop()
function stop(cbFnc)
    log.info("audio.stop",cbFnc)
    if #audioQueue==0 then
        if cbFnc then cbFnc(0) end
    else
        table.insert(audioQueue,{type="STOP",cbFnc=cbFnc})
        sys.publish("LIB_AUDIO_PLAY_IND","STOP")
    end
end

local function audioMsg(msg)
    --log.info("audio.MSG_AUDIO",msg.play_end_ind,msg.play_error_ind)
    sys.publish("LIB_AUDIO_PLAY_IND","RESULT",msg.play_end_ind)
end

--注册core上报的rtos.MSG_AUDIO消息的处理函数
rtos.on(rtos.MSG_AUDIO,audioMsg)
rtos.on(rtos.MSG_TTSPLY_STATUS, function() log.info("rtos.MSG_TTSPLY_STATUS") sys.publish("LIB_AUDIO_PLAY_IND","RESULT",true) end)
rtos.on(rtos.MSG_TTSPLY_ERROR, function() log.info("rtos.MSG_TTSPLY_ERROR") sys.publish("LIB_AUDIO_PLAY_IND","RESULT",false) end)

--- 设置喇叭音量等级
-- @number vol，音量值为0-7，0为静音
-- @return bool result，设置成功返回true，失败返回false
-- @usage audio.setVolume(7)
function setVolume(vol)
    local result = audiocore.setvol(vol)
    if result then sVolume = vol end
    return result
end

--- 设置通话音量等级
-- @number vol，音量值为0-7，0为静音
-- @return bool result，设置成功返回true，失败返回false
-- @usage audio.setCallVolume(7)
function setCallVolume(vol)
    --local result = audiocore.setsphvol(vol)
    --if result then sCallVolume = vol end
    --return result
    audiocore.setsphvol(vol)
    sCallVolume = vol
    return true
end


--- 设置麦克音量等级
-- @number vol，音量值为0-15，0为静音
-- @return bool result，设置成功返回true,失败返回false
-- @usage audio.setMicVolume(14)
function setMicVolume(vol)
    ril.request("AT+CMIC="..audiocore.LOUDSPEAKER..","..vol)
    return true
end

ril.regRsp("+CMIC",function(cmd,success)
    if success then
        sMicVolume = tonumber(cmd:match("CMIC=%d+,(%d+)"))
    end
end)

--- 获取喇叭音量等级
-- @return number vol，喇叭音量等级
-- @usage audio.getVolume()
function getVolume()
    return sVolume
end

--- 获取通话音量等级
-- @return number vol，通话音量等级
-- @usage audio.getCallVolume()
function getCallVolume()
    return sCallVolume
end

--- 获取麦克音量等级
-- @return number vol，麦克音量等级
-- @usage audio.getMicVolume()
function getMicVolume(vol)
    return sMicVolume
end

--- 设置优先级相同时的播放策略
-- @number strategy，优先级相同时的播放策略；0：表示继续播放正在播放的音频，忽略请求播放的新音频；1：表示停止正在播放的音频，播放请求播放的新音频
-- @return nil
-- @usage audio.setStrategy(0)
-- @usage audio.setStrategy(1)
function setStrategy(strategy)
    sStrategy=strategy
end

--- 设置TTS朗读速度
-- @number speed，速度范围为0-100，默认50
-- @return bool result，设置成功返回true，失败返回false
-- @usage audio.setTTSSpeed(70)
function setTTSSpeed(speed)
    if type(speed) == "number" and speed >= 0 and speed <= 100 then
        ttsSpeed = speed
        return true
    end
end

--- 设置音频输出通道
-- 设置后实时生效
-- @number[opt=2] channel，1：headphone耳机    2：speaker喇叭
-- @return nil
-- @usage
-- 设置为耳机输出：audio.setChannel(1)
-- 设置为喇叭输出：audio.setChannel(2)
function setChannel(channel)
    if tonumber(string.match(rtos.get_version(),"Luat_V(%d+)_"))>=9 then
        audiocore.setchannel(channel)
    else
        ril.request("AT+AUDCH="..(channel==1 and 1 or 2))
    end    
end


--默认音频通道设置为LOUDSPEAKER，因为目前的模块只支持LOUDSPEAKER通道
audiocore.setchannel(audiocore.LOUDSPEAKER)
--默认音量等级设置为4级，4级是中间等级，最低为0级，最高为7级
setVolume(sVolume)
setCallVolume(sCallVolume)
--默认MIC音量等级设置为1级，最低为0级，最高为15级
setMicVolume(sMicVolume)
