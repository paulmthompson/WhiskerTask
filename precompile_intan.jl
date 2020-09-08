using Intan, SpikeSorting, Gtk.ShortNames

myt=Task_NoTask()
myfpga=FPGA(1,[0],usb3=true)
myparams=Algorithm[DetectAbs(),ClusterTemplate(49),AlignProm(),FeatureTime(),ReductionNone(),ThresholdMeanN()];
(myrhd,ss,myfpgas)=makeRHD([myfpga],params=myparams,single_channel_mode=true);

handles = makegui(myrhd,ss,myt,myfpgas);
