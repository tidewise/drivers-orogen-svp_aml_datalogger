# frozen_string_literal: true

using_task_library "iodrivers_base"
require "iodrivers_base/orogen_test_helpers"

using_task_library "svp_aml_datalogger"

import_types_from "base"
import_types_from "svp_aml_datalogger"
import_types_from "iodrivers_base"

describe OroGen.svp_aml_datalogger.Task do
    include IODriversBase::OroGenTestHelpers

    run_live

    attr_reader :task
    attr_reader :to_device
    attr_reader :from_device

    before do
        setup_datalogger_task
    end

    after do
        reply_to_stop_measuring if task&.running?
    end

    it "fails to configure when the driver doesnt get any replies from the " \
       "configuration" do
        expect_execution.scheduler(true)
                        .join_all_waiting_work(false)
                        .to { fail_to_start task }
    end

    it "fails to starts when the driver gets an unexpected reply for the sensor " \
       "metadata" do
        configure_datalogger_task
        # No SV as a measurement
        reply = <<~METADATA
            [SensorMetaData]
            Columns=Port,Model,Serial,Firmware,Parameter,Units,CalDate,CalTime,Accuracy,RangeMin,RangeMax
            [SensorData]
            0,X2-Series,200123,1.0.0,SV,m/s,2026-09-16,11:26:01,0.05,1300,1600
            [MeasurementMetadata]
            Columns=Date,Time,Vbat,Pressure,Depth
            Units=YYYY-MM-DD,HH:MM:SS.hh,V,dbar,m
            >
        METADATA
        expect_execution { task.start! }
            .join_all_waiting_work(false)
            .to { have_one_new_sample(task.io_raw_out_port) }
        expect_execution { send_data(reply) }
            .to do
                fail_to_start(task)
                have_one_new_sample(task.sensor_metadata_port)
            end
    end

    it "configures and starts the task" do
        configure_datalogger_task
        start_datalogger_task

        assert_equal :RUNNING, task.orocos_task.state
    end

    it "writes sensor metadata during startup" do
        configure_datalogger_task

        metadata = start_datalogger_task

        assert_equal %w[Port Model Serial Firmware Parameter
                        Units CalDate CalTime Accuracy RangeMin RangeMax],
                     metadata.sensor_metadata
        assert_equal 1, metadata.sensor_data.size
        assert_equal "0", metadata.sensor_data[0].port
        assert_equal "X2-Series", metadata.sensor_data[0].model
        assert_equal "200123", metadata.sensor_data[0].serial_number
        assert_equal "1.0.0", metadata.sensor_data[0].firmware
        assert_equal "SV", metadata.sensor_data[0].parameter
        assert_equal "m/s", metadata.sensor_data[0].units
        assert_equal Time.new(2026, 9, 16, 11, 26, 1),
                     metadata.sensor_data[0].calibration_date
        assert_equal "0.05", metadata.sensor_data[0].accuracy
        assert_equal 1300, metadata.sensor_data[0].range_min
        assert_equal 1600, metadata.sensor_data[0].range_max
    end

    it "outputs measurements when receiving measurement data" do
        configure_datalogger_task
        start_datalogger_task

        measurement = "2026-09-16,11:26:01.10,8.11,0.25346,1499.773,0.25183*0B\r\n"

        sample = expect_execution { send_data(measurement) }
                 .to { have_one_new_sample task.measurements_port }

        assert_equal Time.local(2026, 9, 16, 11, 26, 1, 100_000), sample.time
        assert_in_delta 8.11, sample.battery_voltage, 1e-5
        assert_in_delta 2534.6, sample.pressure.pascal, 1e-3
        assert_in_delta 1499.773, sample.sound_velocity, 1e-5
        assert_in_delta 0.25183, sample.depth, 1e-5
    end

    it "outputs sensor metadata periodically" do
        configure_datalogger_task
        start_datalogger_task

        metadata = expect_execution
                   .timeout(2)
                   .to { have_one_new_sample task.sensor_metadata_port }
        assert_equal %w[Port Model Serial Firmware Parameter
                        Units CalDate CalTime Accuracy RangeMin RangeMax],
                     metadata.sensor_metadata
        assert_equal 1, metadata.sensor_data.size
        assert_equal "0", metadata.sensor_data[0].port
        assert_equal "X2-Series", metadata.sensor_data[0].model
        assert_equal "200123", metadata.sensor_data[0].serial_number
        assert_equal "1.0.0", metadata.sensor_data[0].firmware
        assert_equal "SV", metadata.sensor_data[0].parameter
        assert_equal "m/s", metadata.sensor_data[0].units
        assert_equal Time.new(2026, 9, 16, 11, 26, 1),
                     metadata.sensor_data[0].calibration_date
        assert_equal "0.05", metadata.sensor_data[0].accuracy
        assert_equal 1300, metadata.sensor_data[0].range_min
        assert_equal 1600, metadata.sensor_data[0].range_max
    end

    def setup_datalogger_task(config: default_config)
        @task = syskit_deploy(
            OroGen.svp_aml_datalogger.Task
                  .deployed_as("svp_aml_datalogger_test")
        )
        @task.properties.io_read_timeout = Time.at(2)
        @task.properties.io_write_timeout = Time.at(2)
        @task.properties.config = config
        @task.properties.metadata_update_interval = Time.at(1)
        @task.properties.verbose = true

        syskit_start_execution_agents(@task)
        @to_device = syskit_create_writer(@task.io_raw_in_port)
        @from_device = syskit_create_reader(@task.io_raw_out_port)
    end

    # The number of configuration commands that the driver sends in the configureHook
    CONFIGURATION_COMMANDS_COUNT = 27

    def configure_datalogger_task
        # Reply with the prompt for each configuration command sent by the driver
        CONFIGURATION_COMMANDS_COUNT.times do
            expect_execution.scheduler(true)
                            .join_all_waiting_work(false)
                            .timeout(1)
                            .to { have_one_new_sample from_device }
            send_data(">")
        end
        # Wait for configure to finish
        expect_execution.to_run
    end

    def start_datalogger_task
        expect_execution { task.start! }
            .join_all_waiting_work(false)
            .to { have_one_new_sample(task.io_raw_out_port) }
        metadata = expect_execution { send_data(default_metadata_reply) }
                   .join_all_waiting_work(false)
                   .to { have_one_new_sample(task.sensor_metadata_port) }
        expect_execution { send_data(">") }
            .to { emit(task.start_event) }
        metadata
    end

    def reply_to_stop_measuring
        expect_execution { task.stop! }
            .join_all_waiting_work(false)
        expect_execution { send_data(">\r\n" * 3) }
            .to { emit task.stop_event }
    end

    def send_data(data)
        to_device.write(make_packet(data))
    end

    def make_packet(text)
        Types.iodrivers_base.RawPacket.new(
            time: Time.now,
            data: text.bytes
        )
    end

    def default_config
        {
            sampling_mode: :SINGLE,
            sampling_trigger: {
                mode: :BY_TIME,
                samples_per_s: 1.0,
                sound_velocity_increment: 0.0,
                pressure_increment: { pascal: 0.0 }
            },
            burst_parameters: {
                samples_per_burst: 0,
                burst_interval: Time.at(0),
                monitor: :SAMPLES
            },
            measured_parameters: 1159, # 0x487 (Date, Time, Vbat, Pressure, SV, Depth)
            derived_parameters: 0,
            monitor_parameters: {
                monitor_format: :COLUMNS,
                robust: true,
                auto_start_after_inactivity: Time.at(0)
            }
        }
    end

    def default_metadata_reply
        <<~METADATA
            [SensorMetaData]
            Columns=Port,Model,Serial,Firmware,Parameter,Units,CalDate,CalTime,Accuracy,RangeMin,RangeMax
            [SensorData]
            0,X2-Series,200123,1.0.0,SV,m/s,2026-09-16,11:26:01,0.05,1300,1600
            [MeasurementMetadata]
            Columns=Date,Time,Vbat,Pressure,SV,Depth
            Units=YYYY-MM-DD,HH:MM:SS.hh,V,dbar,m/s,m
            >
        METADATA
    end
end
