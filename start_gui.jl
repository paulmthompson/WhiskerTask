include("/home/wanglab/Documents/WhiskerTask2/WhiskerTask.jl")

myt=Task_CameraTask()
myfpga=FPGA(1,[0],usb3=true)
myparams=Algorithm[DetectAbs(),ClusterTemplate(49),AlignProm(),FeatureTime(),ReductionNone(),ThresholdMeanN()];
(myrhd,ss,myfpgas)=makeRHD([myfpga],params=myparams,single_channel_mode=true);

handles = makegui(myrhd,ss,myt,myfpgas);

if !isinteractive()
    c = Condition()
    signal_connect(handles.win, :destroy) do widget
        notify(c)
    end
    wait(c)
end
