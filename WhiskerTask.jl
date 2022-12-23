using Intan, SpikeSorting, Gtk.ShortNames, Cairo,BaslerCamera, StatsBase
import Intan

mutable struct Impedance
    pulses::BitArray{1}
    counter::Int64
    current::Float64
    impedance::Float64
    stim_voltage::Float64
    base_voltage::Float64
end

Impedance()=Impedance(falses(Intan.SAMPLES_PER_DATA_BLOCK),1,1.0,1.0,1.0,1.0)

mutable struct cam_param
    c::Gtk.GtkCanvasLeaf
    serial::String
    trigger::Int64
    frame_period::Float64
    connected::Bool
    plot_frame::Array{UInt32,2}
    h::Int32
    w::Int32
end

cam_param(h,w,s="") = cam_param(Canvas(20,20),s,1,20.0,false,zeros(UInt32,w,h),h,w)

#=
Data structure
should be a subtype of Task abstract type
=#
mutable struct Task_CameraTask <: Intan.Task
    cam::Camera
    b::Gtk.GtkBuilder
    impedance::Impedance
    pw::Int64
    period::Int64
    pw_mult::Int64
    period_mult::Int64
    stim_start_time::Float64
    in_stim::Bool
    c::Gtk.GtkCanvasLeaf #View Canvas
    cam1_param::cam_param
    save_path::String
end

#=
Constructors for data type
=#

function Task_CameraTask(config_path = "./config.jl")

    include(config_path)

    b = Builder(filename="./whiskertask.glade")

    #Camera 1
    cam=Camera(cam_1_h,cam_1_w,"./config.json")
    cam_param1 = cam_param(cam_1_h,cam_1_w,cam_1_s)
    push!(b["cam_1_active_box"],cam_param1.c)

    c=Canvas(cam_1_w,cam_1_h)

    push!(b["cam_1_box"], c)
    #Gtk.GAccessor.hexpand(c,true)
    #Gtk.GAccessor.vexpand(c,true)


    handles = Task_CameraTask(cam,b,Impedance(),250,1000,1000,3000,0,false,
    c,cam_param1,"")

    sleep(5.0)
    Gtk.showall(handles.b["win"])

    handles
end

function connect_cb(widget::Ptr,user_data::Tuple{Task_CameraTask})
   han, = user_data

   if !han.cam1_param.connected

       #change_camera_config(han.cam,path)
       #Open by serial number
       #connect(han.cam)
       BaslerCamera.load_configuration(han.cam,han.cam.config_path)
       set_gtk_property!(han.b["cam_1_serial"],:label,han.cam1_param.serial)

       sleep(1.0)

       draw_circle(han.cam1_param,(0,1,0))
       #set_gtk_property!(han.b["cam1_connect_label"],:label,"Connected")

       change_save_path(myt.cam.cam,han.save_path)

       han.cam1_param.connected = true
   end

    nothing
end

function view_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han,fpga = user_data

    if get_gtk_property(han.b["view_button"],:active,Bool)
        Intan.manual_trigger(fpga,0,true)
    else
        #End TTL
        Intan.manual_trigger(fpga,0,false)
    end

    nothing
end

function change_pw(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han, fpga = user_data

    nothing
end

function change_period(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han, fpga  = user_data

    nothing
end

function update_stimulation_parameters(han,fpga)

    han.pw = get_gtk_property(han.b["stim_pw_adj"],:value,Int64)
    han.period = get_gtk_property(han.b["stim_period_adj"],:value,Int64)
    num_pulses = get_gtk_property(han.b["stim_pulses_adj"],:value,Int64)

    if get_gtk_property(han.b["pulse_width_combo"],:active,Int64) == 0
        han.pw_mult = 1000
    elseif get_gtk_property(han.b["pulse_width_combo"],:active,Int64) == 1
        han.pw_mult = 1
    end

    if get_gtk_property(han.b["period_combo"],:active,Int64) == 0
        han.period_mult = 1000
    elseif get_gtk_property(han.b["period_combo"],:active,Int64) == 1
        han.period_mult = 1
    end

    if num_pulses == 1
        fpga.d[3].pulseOrTrain = 0
        fpga.d[3].numPulses = 1

        fpga.d[3].firstPhaseDuration = han.pw * han.pw_mult
        fpga.d[3].refractoryPeriod = han.period * han.period_mult - han.pw * han.pw_mult
        fpga.d[3].pulseTrainPeriod = han.period * han.period_mult - han.pw * han.pw_mult
    else
        fpga.d[3].pulseOrTrain = 1
        fpga.d[3].numPulses = num_pulses

        fpga.d[3].firstPhaseDuration = han.pw * han.pw_mult
        #this effectively sets how long until next stimulation. don't want it to be too long
        fpga.d[3].refractoryPeriod = 1e6 * 10
        fpga.d[3].pulseTrainPeriod = han.period * han.period_mult
    end

    Intan.update_digital_output(fpga,fpga.d[3])

    nothing
end

function update_pico_parameters(han,fpga)

    period = get_gtk_property(han.b["pico_period_adj"],:value,Int64)

    total_time = 1000
    pw_ds = .5 # 50% duty cycle
    pw = round(Int,pw_ds * period)
    inter_burst_duration = 2 * total_time # 2 seconds between each stim epoch
    n_p = div(total_time,period)

    fpga.d[5].pulseOrTrain = 1
    fpga.d[5].numPulses = n_p

    fpga.d[5].firstPhaseDuration = pw * 1000 #On Time
    fpga.d[5].refractoryPeriod = (inter_burst_duration - (n_p * period) + (period-pw)) * 1000
    fpga.d[5].pulseTrainPeriod = (period) * 1000

    Intan.update_digital_output(fpga,fpga.d[5])

    nothing
end

function plot_image(han,img,plot_frame)

     ctx=Gtk.getgc(han.c)

     c_w=width(ctx)
     c_h=height(ctx)

     w,h = size(img)
     Cairo.scale(ctx,c_w/w,c_h/h)

     for i=1:length(img)
        plot_frame[i] = (convert(UInt32,img[i]) << 16) | (convert(UInt32,img[i]) << 8) | img[i]
     end
     stride = Cairo.format_stride_for_width(Cairo.FORMAT_RGB24, w)
     @assert stride == 4*w
     surface_ptr = ccall((:cairo_image_surface_create_for_data,Cairo._jl_libcairo),
                 Ptr{Nothing}, (Ptr{Nothing},Int32,Int32,Int32,Int32),
                 plot_frame, Cairo.FORMAT_RGB24, w, h, stride)

     ccall((:cairo_set_source_surface,Cairo._jl_libcairo), Ptr{Nothing},
     (Ptr{Nothing},Ptr{Nothing},Float64,Float64), ctx.ptr, surface_ptr, 0, 0)

     rectangle(ctx, 0, 0, w, h)

     fill(ctx)

     SpikeSorting.identity_matrix(ctx)
     reveal(han.c)

    nothing
end

function laser_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han,fpga = user_data

    if get_gtk_property(han.b["laser_button"],:active,Bool)
        Intan.manual_trigger(fpga,1,true)
    else
        Intan.manual_trigger(fpga,1,false)
    end

    nothing
end

function stim_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han,fpga = user_data

    if get_gtk_property(han.b["stimulator_button"],:active,Bool)
        update_stimulation_parameters(han,fpga)
        Intan.manual_trigger(fpga,2,true)
    else
        Intan.manual_trigger(fpga,2,false)
    end

    nothing
end

function pico_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han, fpga = user_data

    if get_gtk_property(han.b["pico_button"],:active,Bool)
        update_pico_parameters(han,fpga)
        Intan.manual_trigger(fpga,4,true)
    else
        Intan.manual_trigger(fpga,4,false)
    end

    nothing
end

function change_ffmpeg_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,Intan.Gui_Handles})

    myt,han = user_data

    base_path = get_gtk_property(han.save_widgets.input,:text,String)

    change_save_path(myt.cam.cam,string(base_path,"/output.mp4"))

    nothing
end

function recording_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,Intan.Gui_Handles,FPGA,Intan.RHD2000})

    myt,han,fpga,rhd = user_data

    if get_gtk_property(han.record,:active,Bool)

        #we may want to make sure that the ttl box is checked. Perhaps this one should be on by default?

        #If camera is in view mode, we will be collecting frames already
        #Turn off briefly
        if get_gtk_property(myt.b["view_button"],:active,Bool)
            set_gtk_property!(myt.b["view_button"],:active,false)
        end

        #We wait here for everything to power down. Ideally we could flush the camera
        sleep(1.0)

        #Start ffmpeg
        #start_ffmpeg(myt.cam.cam)
        set_record(myt.cam.cam,true)

        #Wait for ffmpeg to get loaded up
        sleep(1.0)

        #Start TTL
        set_gtk_property!(myt.b["view_button"],:active,true)

    else #turn off

        #Turn off camera
        set_gtk_property!(myt.b["view_button"],:active,false)

        #Let ffmpeg finish, I should be waiting for a done signal here.
        sleep(5.0)

        set_record(myt.cam.cam,false)

        sleep(5.0)

        check_alignment(rhd)
    end

    nothing
end

function check_alignment(rhd)

    analog_path = rhd.save.ttl

    vid_path = string(rhd.save.folder,"/output.mp4")

    xx=read(`mediainfo --Output="Video;%FrameCount%" $(vid_path)`)
    if length(xx) < 2
        video_frames = 0
    else
        video_frames=parse(Int64,String(xx[1:(end-1)]))
    end

    analog_size=length(findall(diff(Intan.parse_ttl(analog_path)[2]).>1))

    println("Video Frames: ", video_frames)
    println("Analog Data: ", analog_size)
    if (video_frames == analog_size)
        println("Yay, frames match!")
    else
        println("Boo! Frame mismatch by ", abs(video_frames-analog_size))
    end
end

function calculate_impedance(myt,fpga)

    adc_gain = get_gtk_property(myt.b["impedance_adc_gain_adj"],:value,Float64)
    adc_input=6
    stim_control_ttl=3

    if get_gtk_property(myt.b["calc_impedance_button"],:active,Bool)

        myt.impedance.current = get_gtk_property(myt.b["impedance_current_adj"],:value,Float64)

        for i=1:length(fpga.ttlout)
            myt.impedance.pulses[i]=false
            if (fpga.ttlout[i] & (1 << (stim_control_ttl-1))) > 0
                myt.impedance.pulses[i]=true
            end
        end

        if sum(myt.impedance.pulses) > (length(myt.impedance.pulses)*.75)
            myt.impedance.stim_voltage=mean(fpga.adc[myt.impedance.pulses,adc_input])

            dv = myt.impedance.stim_voltage - myt.impedance.base_voltage
            dv = dv * (10.24*2) / typemax(UInt16) * 1000 / adc_gain
            myt.impedance.impedance = round(dv / myt.impedance.current,digits=2)
            set_gtk_property!(myt.b["impedance_label"],:label,string(myt.impedance.impedance))
        else
            myt.impedance.base_voltage=mean(fpga.adc[.!myt.impedance.pulses,adc_input])
            v = myt.impedance.base_voltage * (10.24*2) / typemax(UInt16) * 1000
            set_gtk_property!(myt.b["impedance_voltage"],:label,string(round(v,digits=1)))
        end


    end
end

function draw_circle(cam::cam_param,color::Tuple)
    ctx = Gtk.getgc(cam.c)

    set_source_rgb(ctx, color...)
    arc(ctx, 10, 10, 9, 0, 2pi)
    stroke_preserve(ctx)
    fill(ctx)
    reveal(cam.c)
end

function setup_pico(fpga::FPGA)

    total_time = 1000
    inter_burst_duration = 2 * total_time
    n_p = 100
    pw_ds = 0.5
    period = 10
    pw = round(Int,pw_ds * period)

    fpga.d[5].channel=4
    fpga.d[5].pulseOrTrain = 1

    fpga.d[5].triggerEnabled=1
    fpga.d[5].triggerSource=28

    fpga.d[5].numPulses = n_p
    fpga.d[5].postTriggerDelay=0
    fpga.d[5].firstPhaseDuration=pw * 1000
    fpga.d[5].refractoryPeriod = (inter_burst_duration - (n_p * period) + (period-pw)) * 1000
    fpga.d[5].pulseTrainPeriod = (period) * 1000

    Intan.update_digital_output(fpga,fpga.d[5])
    nothing
end


#=
Initialization function
This will build all of the necessary elements before anything starts running
(initializing external boards, creating GUIs etc)
=#
function Intan.init_task(myt::Task_CameraTask,rhd::Intan.RHD2000,han,fpga)

    #Yoke together change in save filename textbox with ffmpeg folder
    signal_connect(change_ffmpeg_cb,han.save_widgets.input,"activate",Nothing,(),false,(myt,han))

    #Clicking Record in Main GUI starts the Camera Recording
    signal_connect(recording_cb, han.record,"toggled",Nothing,(),false,(myt,han,fpga[1],rhd))


    signal_connect(connect_cb,myt.b["connect_button"],"clicked",Nothing,(),false,(myt,))
    signal_connect(view_cb,myt.b["view_button"],"toggled",Nothing,(),false,(myt,fpga[1]))
    signal_connect(laser_cb,myt.b["laser_button"],"toggled",Nothing,(),false,(myt,fpga[1]))

    signal_connect(change_pw,myt.b["stim_pw_sb"],"value-changed",Nothing,(),false,(myt,fpga[1]))
    signal_connect(change_period,myt.b["stim_period_sb"],"value-changed",Nothing,(),false,(myt,fpga[1]))
    signal_connect(stim_cb,myt.b["stimulator_button"],"toggled",Nothing,(),false,(myt,fpga[1]))

    signal_connect(pico_cb,myt.b["pico_button"],"toggled",Nothing,(),false,(myt,fpga[1]))

    #For this experiment, we want to be recording voltage, timestamps, and TTLs
    set_gtk_property!(han.save_widgets.ts,:active,true)
    set_gtk_property!(han.save_widgets.volt,:active,true)
    set_gtk_property!(han.save_widgets.ttlin,:active,true)

    draw_circle(myt.cam1_param,(1,0,0))

    #Stimulation Parameters
    #TTL 1 is camera at 500 fps
    fpga[1].d[1].channel=0
    fpga[1].d[1].pulseOrTrain = 0

    fpga[1].d[1].triggerEnabled=1
    fpga[1].d[1].triggerSource=24

    fpga[1].d[1].numPulses=1
    fpga[1].d[1].postTriggerDelay=0
    fpga[1].d[1].firstPhaseDuration=1000 #1 ms
    fpga[1].d[1].refractoryPeriod=1000 # 1 ms
    Intan.update_digital_output(fpga[1],fpga[1].d[1])

    #TTL 2 is laser at
    fpga[1].d[2].channel=1
    fpga[1].d[2].pulseOrTrain = 0

    fpga[1].d[2].triggerEnabled=1
    fpga[1].d[2].triggerSource=25

    fpga[1].d[2].numPulses=1
    fpga[1].d[2].postTriggerDelay=0
    fpga[1].d[2].firstPhaseDuration=2000 #2 ms
    fpga[1].d[2].refractoryPeriod=48000 # 48 ms
    Intan.update_digital_output(fpga[1],fpga[1].d[2])

    #TTL 3 is juxtacellular stimulation
    fpga[1].d[3].channel=2
    fpga[1].d[3].pulseOrTrain = 0

    fpga[1].d[3].triggerEnabled=1
    fpga[1].d[3].triggerSource=26

    fpga[1].d[3].numPulses=1
    fpga[1].d[3].postTriggerDelay=0
    fpga[1].d[3].firstPhaseDuration = 250000 # 250 ms
    fpga[1].d[3].refractoryPeriod = 1000000 - 250000 # 3 seconds
    Intan.update_digital_output(fpga[1],fpga[1].d[3])

    setup_pico(fpga[1])

    #set TTL output #4 as high
    Intan.setTtlMode(fpga[1],[false,false,false,true,false,false,false,false])
    Intan.manual_trigger(fpga[1],3,true)

    myt.save_path = string(rhd.save.folder,"/output.mp4")

    nothing
end

#=
Experimental Control Function
This will implement the control logic of the task
such as updating GUIs, modifying the data structure, talking to external boards
=#
function Intan.do_task(myt::Task_CameraTask,rhd::Intan.RHD2000,myread,han,fpga)

    #Draw Picture
    if (myread)

        (myimage,grabbed) = BaslerCamera.get_data(myt.cam)
        
        if (grabbed > 0)
            plot_image(myt,myimage,myt.cam1_param.plot_frame)
        end

        calculate_impedance(myt,fpga[1])

    end

    nothing
end

#=
Logging Function
This will save the appropriate elements of the data structure, as well as specifying what
analog streams from either the Intan or other external DAQs
=#
function Intan.save_task(myt::Task_CameraTask,rhd::Intan.RHD2000)
end
