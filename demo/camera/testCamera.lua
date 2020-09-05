--- 模块功能：camera功能测试.
-- @author openLuat
-- @module fs.testFs
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.27

module(...,package.seeall)

require"pm"
require"scanCode"
require"utils"
require"common"
require"testUartSentFile"

local WIDTH,HEIGHT = disp.getlcdinfo()
local DEFAULT_WIDTH,DEFAULT_HEIGHT = 320,240

-- 扫码结果回调函数
-- @bool result，true或者false，true表示扫码成功，false表示超时失败
-- @string[opt=nil] codeType，result为true时，表示扫码类型；result为false时，为nil；支持QR-Code和CODE-128两种类型
-- @string[opt=nil] codeStr，result为true时，表示扫码结果的字符串；result为false时，为nil
local function scanCodeCb(result,codeType,codeStr)
    --关闭摄像头预览
    disp.camerapreviewclose()
    --关闭摄像头
    disp.cameraclose()
    --允许系统休眠
    pm.sleep("testScanCode")
    --500毫秒后处理扫描结果
    sys.timerStart(function()
        --如果有LCD，显示扫描结果
        if WIDTH~=0 and HEIGHT~=0 then 
            disp.clear()
            if result then
                disp.puttext(common.utf8ToGb2312("扫描成功"),0,5)
                disp.puttext(common.utf8ToGb2312("类型: ")..codeType,0,35)
                log.info("scanCodeCb",codeStr:toHex())
                disp.puttext(common.utf8ToGb2312("结果: ")..codeStr,0,65)                
            else
                disp.puttext(common.utf8ToGb2312("扫描失败"),0,5)                
            end
            disp.update()
        end
    end,500)
    
    sys.timerStart(scan,5000)
end

--扫码
function scan()
    --唤醒系统
    pm.wake("testScanCode")
    --设置扫码回调函数，默认10秒超时
    scanCode.request(scanCodeCb)
    --打开摄像头
    disp.cameraopen(1,1)
    --打开摄像头预览
    --如果有LCD，使用LCD的宽和高
    --如果无LCD，宽度设置为240像素，高度设置为320像素，240*320是Air268F支持的最大分辨率
    disp.camerapreview(0,0,0,0,WIDTH or DEFAULT_WIDTH,HEIGHT or DEFAULT_HEIGHT)
end




-- 拍照并显示
function takePhotoAndDisplay()
    --唤醒系统
    pm.wake("testTakePhoto")
    --打开摄像头
    disp.cameraopen(1,0,0,1)
    --disp.cameraopen(1,0,0,0)  --因目前core中还有问题没解决，所以不能关闭隔行隔列
    --打开摄像头预览
    --如果有LCD，使用LCD的宽和高
    --如果无LCD，宽度设置为240像素，高度设置为320像素，240*320是Air268F支持的最大分辨率
    disp.camerapreview(0,0,0,0,WIDTH or DEFAULT_WIDTH,HEIGHT or DEFAULT_HEIGHT)
    --设置照片的宽和高像素并且开始拍照
    --此处设置的宽和高和预览时的保持一致
    --此处的第三个参数表示拍摄质量，默认50，100最好
    disp.cameracapture(WIDTH or DEFAULT_WIDTH,HEIGHT or DEFAULT_HEIGHT)
    --设置照片保存路径
    disp.camerasavephoto("/testCamera.jpg")
    log.info("testCamera.takePhotoAndDisplay fileSize",io.fileSize("/testCamera.jpg"))
    --关闭摄像头预览
    disp.camerapreviewclose()
    --关闭摄像头
    disp.cameraclose()
    --允许系统休眠
    pm.sleep("testTakePhoto")    

    --testUartSentFile.sendFile()
    --显示拍照图片   
    if WIDTH~=0 and HEIGHT~=0 then
        disp.clear()
        disp.putimage("/testCamera.jpg",0,0)
        disp.puttext(common.utf8ToGb2312("照片尺寸: "..io.fileSize("/testCamera.jpg")),0,5)
        disp.update()
    end   
    
    sys.timerStart(takePhotoAndDisplay,5000)    
end


-- 拍照并通过uart1发送出去
function takePhotoAndSendToUart()
    --唤醒系统
    pm.wake("testTakePhoto")
    --打开摄像头
    disp.cameraopen(1,0,0,1)
    --disp.cameraopen(1,0,0,0)  --因目前core中还有问题没解决，所以不能关闭隔行隔列
    --打开摄像头预览
    --如果有LCD，使用LCD的宽和高
    --如果无LCD，宽度设置为240像素，高度设置为320像素，240*320是Air268F支持的最大分辨率
    disp.camerapreview(0,0,0,0,DEFAULT_WIDTH,DEFAULT_HEIGHT)
    --设置照片的宽和高像素并且开始拍照
    --此处设置的宽和高和预览时的保持一致
    disp.cameracapture(DEFAULT_WIDTH,DEFAULT_HEIGHT)
    --设置照片保存路径
    disp.camerasavephoto("/testCamera.jpg")
    log.info("testCamera.takePhotoAndSendToUart fileSize",io.fileSize("/testCamera.jpg"))
    --关闭摄像头预览
    disp.camerapreviewclose()
    --关闭摄像头
    disp.cameraclose()
    --允许系统休眠
    pm.sleep("testTakePhoto")    

    testUartSentFile.sendFile()     
    
    sys.timerStart(takePhotoAndSendToUart,30000)    
end

--sys.timerStart(takePhotoAndDisplay,1000)
--sys.timerStart(takePhotoAndSendToUart,1000)
sys.timerStart(scan,1000)
