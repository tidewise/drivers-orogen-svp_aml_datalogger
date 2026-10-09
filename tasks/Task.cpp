/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include <base-logging/Logging.hpp>
#include <iodrivers_base/ConfigureGuard.hpp>
#include <memory>
#include <svp_aml_datalogger/Driver.hpp>
#include <svp_aml_datalogger/Task.hpp>

using namespace svp_aml_datalogger;

Task::Task(std::string const& name)
    : TaskBase(name)
{
    _metadata_update_interval.set(base::Time::fromSeconds(60));
}

Task::~Task()
{
}

bool Task::configureHook()
{
    iodrivers_base::ConfigureGuard guard(this);
    auto verbose = _verbose.get();
    auto configuration = _config.get();
    configuration.validate();
    auto driver = std::make_unique<Driver>(configuration, verbose);
    if (!_io_port.get().empty()) {
        driver->openURI(_io_port.get());
    }

    setDriver(driver.get());
    if (!TaskBase::configureHook()) {
        return false;
    }
    m_driver = std::move(driver);

    m_metadata_update_timeout = _metadata_update_interval.get();
    m_metadata_update_deadline = base::Time::now() + m_metadata_update_timeout;

    try {
        m_driver->configure();
    }
    catch (std::exception const& e) {
        LOG_ERROR_S << "Failed to configure the device: " << e.what();
        return false;
    }

    guard.commit();
    return true;
}

bool Task::startHook()
{
    if (!TaskBase::startHook()) {
        return false;
    }

    try {
        m_metadata = m_driver->displaySensorsParsed();
        _sensor_metadata.write(m_metadata);

        m_driver->startMeasuring(m_metadata);
    }
    catch (std::exception const& e) {
        LOG_ERROR_S << "Failed to start measuring: " << e.what();
        return false;
    }

    return true;
}

void Task::updateHook()
{
    TaskBase::updateHook();

    updateMetadata();
}

void Task::errorHook()
{
    TaskBase::errorHook();
}

void Task::stopHook()
{
    TaskBase::stopHook();

    try {
        m_driver->stopMeasuring();
    }
    catch (std::exception const& e) {
        LOG_ERROR_S << "Failed to stop measuring: " << e.what();
    }
}

void Task::cleanupHook()
{
    TaskBase::cleanupHook();

    m_driver.reset();
}

void Task::processIO()
{
    auto measurements = m_driver->readMeasurements();
    if (measurements.has_value()) {
        _measurements.write(*measurements);
    }
}

void Task::updateMetadata()
{
    if (base::Time::now() < m_metadata_update_deadline) {
        return;
    }

    // Do not output the metadata fresh from the sensor. It would require stopping the
    // measurements and it is in fact static.
    _sensor_metadata.write(m_metadata);
    m_metadata_update_deadline = base::Time::now() + m_metadata_update_timeout;
}
