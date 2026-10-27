/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "SVPAltitudeMultiplexerTask.hpp"
#include <base-logging/Logging.hpp>

using namespace svp_aml_datalogger;
using namespace base::samples;

SVPAltitudeMultiplexerTask::SVPAltitudeMultiplexerTask(std::string const& name)
    : SVPAltitudeMultiplexerTaskBase(name)
{
}

SVPAltitudeMultiplexerTask::~SVPAltitudeMultiplexerTask()
{
}

/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See SVPAltitudeMultiplexerTask.hpp for more detailed
// documentation about them.

bool SVPAltitudeMultiplexerTask::configureHook()
{
    if (!SVPAltitudeMultiplexerTaskBase::configureHook())
        return false;
    m_minimum_depth = _minimum_depth.get();

    return true;
}
bool SVPAltitudeMultiplexerTask::startHook()
{
    if (!SVPAltitudeMultiplexerTaskBase::startHook())
        return false;
    return true;
}
void SVPAltitudeMultiplexerTask::updateHook()
{
    SVPAltitudeMultiplexerTaskBase::updateHook();

    Joints joint_status;
    if (_motor_feedback.read(joint_status) == RTT::NoData) {
        return;
    }
    if (!validateMotorFeedback(joint_status)) {
        return;
    }
    Measurements measurements;
    if (_measurements.read(measurements) != RTT::NoData) {
        evaluateWaterLevelState(joint_status, measurements.depth);
    }
    else {
        m_state = UNKNOWN;
    }

    if (state() != m_state) {
        state(m_state);
    }

    _altitude.write(joint_status);
}

void SVPAltitudeMultiplexerTask::evaluateWaterLevelState(Joints& joint, double depth)
{
    if (depth <= m_minimum_depth) {
        m_state = IN_WATER;
        joint.elements[0].position = depth;
    }
    else {
        m_state = OUT_OF_WATER;
    }
    joint.time = base::Time::now();
}

bool SVPAltitudeMultiplexerTask::validateMotorFeedback(Joints const& joint_status)
{
    if (joint_status.elements.size() != 1) {
        LOG_ERROR_S << "Expected a motor feedback with 1 joint but got "
                    << joint_status.elements.size();
        exception(INVALID_MOTOR_FEEDBACK);
        return false;
    }

    auto joint = joint_status.elements.front();
    if (!joint.hasPosition()) {
        LOG_ERROR_S << "Expected a motor feedback with position, but it doenst";
        exception(INVALID_MOTOR_FEEDBACK);
        return false;
    }
    return true;
}

void SVPAltitudeMultiplexerTask::errorHook()
{
    SVPAltitudeMultiplexerTaskBase::errorHook();
}
void SVPAltitudeMultiplexerTask::stopHook()
{
    SVPAltitudeMultiplexerTaskBase::stopHook();
}
void SVPAltitudeMultiplexerTask::cleanupHook()
{
    SVPAltitudeMultiplexerTaskBase::cleanupHook();
}
