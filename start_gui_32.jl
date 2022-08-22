include("/home/wanglab/Documents/WhiskerTask2/WhiskerTask.jl")

myamp=RHD2132("PortA1")
myt=Task_CameraTask()
myfpga=FPGA(1,myamp,usb3=true)
myparams=Algorithm[DetectAbs(),ClusterTemplate(49),AlignProm(),FeatureTime(),ReductionNone(),ThresholdMeanN()];
(myrhd,ss,myfpgas)=makeRHD([myfpga],params=myparams);

handles = makegui(myrhd,ss,myt,myfpgas);

if !isinteractive()
    c = Condition()
    signal_connect(handles.win, :destroy) do widget
        notify(c)
    end
    wait(c)
end
