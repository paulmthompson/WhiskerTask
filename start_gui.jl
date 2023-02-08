include("/home/wanglab/Documents/WhiskerTask/WhiskerTask.jl")

sampleRate=30000
myt=Task_CameraTask()
myfpga=FPGA(1,[0],usb3=true,sr=sampleRate)
myparams=Algorithm[DetectAbs(),ClusterTemplate(49),AlignProm(),FeatureTime(),ReductionNone(),ThresholdMeanN()];
(myrhd,ss,myfpgas)=makeRHD([myfpga],params=myparams,single_channel_mode=true,sr=sampleRate);

handles = makegui(myrhd,ss,myt,myfpgas);

if !isinteractive()
    c = Condition()
    signal_connect(handles.win, :destroy) do widget
        notify(c)
    end
    wait(c)
end
