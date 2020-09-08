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

#=
Data structure
should be a subtype of Task abstract type
=#
mutable struct Task_CameraTask <: Intan.Task
    cam::Camera
    win::Gtk.GtkWindowLeaf #Window
    c_button::Gtk.GtkButtonLeaf #Connect Button
    v_button::Gtk.GtkToggleButtonLeaf #View Button
    stim_button::Gtk.GtkToggleButtonLeaf
    stim_pulse_width_button::Gtk.GtkSpinButtonLeaf
    stim_period_button::Gtk.GtkSpinButtonLeaf
    stim_pulses_button::Gtk.GtkSpinButtonLeaf
    calculate_impedance::Gtk.GtkCheckButtonLeaf
    impedance_label::Gtk.GtkLabelLeaf
    impedance_voltage_label::Gtk.GtkLabelLeaf
    impedance_current::Gtk.GtkSpinButtonLeaf
    impedance::Impedance
    pw::Int64
    period::Int64
    stim_start_time::Float64
    in_stim::Bool
    c::Gtk.GtkCanvasLeaf #View Canvas
    l_button::Gtk.GtkToggleButtonLeaf #Laser Button
    plot_frame::Array{UInt32,2}
    n_camera::Int32
    #Phototag Laser Control
end

#=
Constructors for data type
=#

function Task_CameraTask(w=640,h=480,n_camera=1)

    cam=Camera(h,w,1,n_camera)

    upper_grid=Grid()
    grid=Grid()

    c_button = Button("Connect")
    upper_grid[1,1] = c_button

    v_button = ToggleButton("View")
    upper_grid[2,1] = v_button

    l_button = ToggleButton("Laser")
    upper_grid[3,1] = l_button

    stim_button = ToggleButton("Stimulate")
    upper_grid[4,1] = stim_button

    stim_pulse_width = SpinButton(1:1000)
    Gtk.GAccessor.value(stim_pulse_width,250)
    upper_grid[4,2] = stim_pulse_width
    upper_grid[3,2] = Label("Pulse Width")

    stim_period = SpinButton(1:10000)
    Gtk.GAccessor.value(stim_period,3000)
    upper_grid[4,3] = stim_period
    upper_grid[3,3] = Label("Period")

    stim_pulses = SpinButton(1:1000)
    Gtk.GAccessor.value(stim_pulses,1)
    upper_grid[4,4] = stim_pulses
    upper_grid[3,4] = Label("Num Pulses")

    calc_impedance_button = CheckButton("Calculate Impedance")
    upper_grid[5,1] = calc_impedance_button

    impedance_current = SpinButton(0.0:0.1:10.0)
    upper_grid[5,2] = impedance_current
    upper_grid[6,2] = Label("Current (nA)")

    impedance_grid=Grid()
    impedance_grid[1,1]=Label("Impedance: ")
    impedance_label=Label("")
    impedance_grid[2,1]=impedance_label
    upper_grid[5,3] = impedance_grid

    impedance_grid[1,2]=Label("Voltage (mV): ")
    impedance_voltage_label=Label("")
    impedance_grid[2,2]=impedance_voltage_label

    grid[1,1] = upper_grid

    c=Canvas(-1,-1)

    grid[1,2] = c
    Gtk.GAccessor.hexpand(c,true)
    Gtk.GAccessor.vexpand(c,true)

    win = Window(grid, "Control") |> Gtk.showall

    handles = Task_CameraTask(cam,win,c_button,v_button,
    stim_button,stim_pulse_width,stim_period,stim_pulses,calc_impedance_button,
    impedance_label,impedance_voltage_label,impedance_current,Impedance(),250,3000,0,false,
    c,l_button,zeros(UInt32,w,h*n_camera),n_camera)

    sleep(5.0)

    plot_image(handles,zeros(UInt8,w,h*n_camera))

    handles
end

function connect_cb(widget::Ptr,user_data::Tuple{Task_CameraTask})
   han, = user_data

    connect(han.cam)

    start_acquisition(han.cam)

    nothing
end

function view_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han,fpga = user_data

    if get_gtk_property(han.v_button,:active,Bool)
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

    han.pw = get_gtk_property(han.stim_pulse_width_button,:value,Int64)
    han.period = get_gtk_property(han.stim_period_button,:value,Int64)
    num_pulses = get_gtk_property(han.stim_pulses_button,:value,Int64)

    if num_pulses == 1
        fpga.d[3].pulseOrTrain = 0
        fpga.d[3].numPulses = 1

        fpga.d[3].firstPhaseDuration = han.pw * 1000
        fpga.d[3].refractoryPeriod = (han.period - han.pw) * 1000
        fpga.d[3].pulseTrainPeriod = (han.period - han.pw) * 1000
    else
        fpga.d[3].pulseOrTrain = 1
        fpga.d[3].numPulses = num_pulses

        fpga.d[3].firstPhaseDuration = han.pw * 1000
        #this effectively sets how long until next stimulation. don't want it to be too long
        fpga.d[3].refractoryPeriod = 1e6 * 10
        fpga.d[3].pulseTrainPeriod = han.period * 1000
    end

    Intan.update_digital_output(fpga,fpga.d[3])

    nothing
end

function plot_image(han,img)

     ctx=Gtk.getgc(han.c)

     c_w=width(ctx)
     c_h=height(ctx)

     w,h = size(img)
     Cairo.scale(ctx,c_w/w,c_h/h)

     for i=1:length(img)
        han.plot_frame[i] = (convert(UInt32,img[i]) << 16) | (convert(UInt32,img[i]) << 8) | img[i]
     end
     stride = Cairo.format_stride_for_width(Cairo.FORMAT_RGB24, w)
     @assert stride == 4*w
     surface_ptr = ccall((:cairo_image_surface_create_for_data,Cairo._jl_libcairo),
                 Ptr{Nothing}, (Ptr{Nothing},Int32,Int32,Int32,Int32),
                 han.plot_frame, Cairo.FORMAT_RGB24, w, h, stride)

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

    if get_gtk_property(han.l_button,:active,Bool)
        Intan.manual_trigger(fpga,1,true)
    else
        Intan.manual_trigger(fpga,1,false)
    end

    nothing
end

function stim_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,FPGA})

    han,fpga = user_data

    if get_gtk_property(han.stim_button,:active,Bool)
        update_stimulation_parameters(han,fpga)
        Intan.manual_trigger(fpga,2,true)
    else
        Intan.manual_trigger(fpga,2,false)
    end

    nothing
end

function change_ffmpeg_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,Intan.Gui_Handles})

    myt,han = user_data

    base_path = get_gtk_property(han.save_widgets.input,:text,String)

    change_ffmpeg_folder(myt.cam.cam,base_path)

    nothing
end

function recording_cb(widget::Ptr,user_data::Tuple{Task_CameraTask,Intan.Gui_Handles,FPGA,Intan.RHD2000})

    myt,han,fpga,rhd = user_data

    if get_gtk_property(han.record,:active,Bool)

        #we may want to make sure that the ttl box is checked. Perhaps this one should be on by default?

        #If camera is in view mode, we will be collecting frames already
        #Turn off briefly
        if get_gtk_property(myt.v_button,:active,Bool)
            set_gtk_property!(myt.v_button,:active,false)
        end

        #We wait here for everything to power down. Ideally we could flush the camera
        sleep(1.0)

        #Start ffmpeg
        start_ffmpeg(myt.cam.cam)

        #Wait for ffmpeg to get loaded up
        sleep(1.0)

        #Start TTL
        set_gtk_property!(myt.v_button,:active,true)

    else #turn off

        #Turn off camera
        set_gtk_property!(myt.v_button,:active,false)

        #Let ffmpeg finish
        sleep(2.0)

        end_ffmpeg(myt.cam.cam)

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

    adc_input=6
    stim_control_ttl=3

    if get_gtk_property(myt.calculate_impedance,:active,Bool)

        myt.impedance.current = get_gtk_property(myt.impedance_current,:value,Float64)

        for i=1:length(fpga.ttlout)
            myt.impedance.pulses[i]=false
            if (fpga.ttlout[i] & (1 << (stim_control_ttl-1))) > 0
                myt.impedance.pulses[i]=true
            end
        end

        if sum(myt.impedance.pulses) > (length(myt.impedance.pulses)*.75)
            myt.impedance.stim_voltage=mean(fpga.adc[myt.impedance.pulses,adc_input])

            dv = myt.impedance.stim_voltage - myt.impedance.base_voltage
            dv = dv * (10.24*2) / typemax(UInt16) * 1000
            myt.impedance.impedance = round(dv / myt.impedance.current,digits=2)
            set_gtk_property!(myt.impedance_label,:label,string(myt.impedance.impedance))
        else
            myt.impedance.base_voltage=mean(fpga.adc[.!myt.impedance.pulses,adc_input])
            v = myt.impedance.base_voltage * (10.24*2) / typemax(UInt16) * 1000
            set_gtk_property!(myt.impedance_voltage_label,:label,string(round(v,digits=1)))
        end


    end
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


    signal_connect(connect_cb,myt.c_button,"clicked",Nothing,(),false,(myt,))
    signal_connect(view_cb,myt.v_button,"toggled",Nothing,(),false,(myt,fpga[1]))
    signal_connect(laser_cb,myt.l_button,"toggled",Nothing,(),false,(myt,fpga[1]))

    signal_connect(change_pw,myt.stim_pulse_width_button,"value-changed",Nothing,(),false,(myt,fpga[1]))
    signal_connect(change_period,myt.stim_period_button,"value-changed",Nothing,(),false,(myt,fpga[1]))
    signal_connect(stim_cb,myt.stim_button,"toggled",Nothing,(),false,(myt,fpga[1]))

    change_ffmpeg_folder(myt.cam,rhd.save.folder)

    #For this experiment, we want to be recording voltage, timestamps, and TTLs
    set_gtk_property!(han.save_widgets.ts,:active,true)
    set_gtk_property!(han.save_widgets.volt,:active,true)
    set_gtk_property!(han.save_widgets.ttlin,:active,true)

    #Stimulation Parameters
    #TTL 1 is camera at 500 fps
    fpga[1].d[1].channel=0
    fpga[1].d[1].pulseOrTrain = 0

    fpga[1].d[1].triggerEnabled=1
    fpga[1].d[1].triggerSource=24

    fpga[1].d[1].numPulses=1
    fpga[1].d[1].postTriggerDelay=0
    fpga[1].d[1].firstPhaseDuration=1000
    fpga[1].d[1].refractoryPeriod=1000
    Intan.update_digital_output(fpga[1],fpga[1].d[1])

    #TTL 2 is laser at
    fpga[1].d[2].channel=1
    fpga[1].d[2].pulseOrTrain = 0

    fpga[1].d[2].triggerEnabled=1
    fpga[1].d[2].triggerSource=25

    fpga[1].d[2].numPulses=1
    fpga[1].d[2].postTriggerDelay=0
    fpga[1].d[2].firstPhaseDuration=2000 #2 ms
    fpga[1].d[2].refractoryPeriod=8000
    Intan.update_digital_output(fpga[1],fpga[1].d[2])

    #TTL 3 is juxtacellular stimulation
    fpga[1].d[3].channel=2
    fpga[1].d[3].pulseOrTrain = 0

    fpga[1].d[3].triggerEnabled=1
    fpga[1].d[3].triggerSource=26

    fpga[1].d[3].numPulses=1
    fpga[1].d[3].postTriggerDelay=0
    fpga[1].d[3].firstPhaseDuration = 250000 #250 ms
    fpga[1].d[3].refractoryPeriod = 1000000 - 250000#3 seconds
    Intan.update_digital_output(fpga[1],fpga[1].d[3])

    #set TTL output #4 as high
    Intan.setTtlMode(fpga[1],[false,false,false,true,false,false,false,false])
    Intan.manual_trigger(fpga[1],3,true)

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
        (myimage,grabbed) = get_data(myt.cam)

        if (grabbed)
            plot_image(myt,myimage)
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
