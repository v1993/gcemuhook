/* AbstractPhysicalDevice.vala
 *
 * Copyright 2022 v1993 <v19930312@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * 	http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

namespace Cemuhook {
	/**
	 * Interface that represents physical device exposable via {@link Server}
	 *
	 * Note: device should not generally assume that it's added to only one server.
	 * While this is a rare case, it's correctly supported by gCemuhook's Server.
	 *
	 * Additionally, avoid storing pointers to server(s). Then may become invalid and/or
	 * result in memory leaks due to cyclic references.
	 */
	public abstract interface AbstractPhysicalDevice : Object {
		/**
		 * Signals device disconnection event, connected to by Server.
		 *
		 * You *must* call this when your device disconnects.
		 * This will trigger destruction of device object if no other references are held to it.
		 */
		public signal void disconnected();

		/**
		 * Signals that new data packet is ready, connected to by Server.
		 *
		 * You must call this when new complete data packet was received from physical device.
		 * This will trigger sending for all active clients, thus resulting in calls that obtain
		 * data from your device.
		 */
		public signal void updated();

		/**
		 * Called right after device is added to server.
		 */
		public signal void added(Server server);

		/**
		 * Called right before device is removed from server.
		 *
		 * A raw pointer is used because this may be called during server's destruction. As such,
		 * it's not recommended to call any server methods here.
		 */
		public signal void removed(Server* server);

		/**
		 * Get device's motion capabilities.
		 *
		 * Depending on result, {@link get_accelerometer} and {@link get_gyro} will
		 * or will not be called.
		 */
		public abstract DeviceType get_device_type();

		/**
		 * Get device's connection type.
		 *
		 * This is a very low-importance data, so feel free to left it unimplemented if it's not
		 * worth the effort.
		 */
		public virtual ConnectionType get_connection_type() { return OTHER; }

		/**
		 * Get device's unique 48-bit identifier.
		 *
		 * Two devices should never have the same value, with exception of zero,
		 * which is used to indicate that device lack a meaningful unique identifier.
		 *
		 */
		public virtual uint64 get_mac()
		ensures ((result >> 48) == 0)
			{ return 0; }

		/**
		 * Get battery status of device.
		 *
		 * This is a medium-priority information, so it's recommended to implement it if possible.
		 */
		public virtual BatteryStatus get_battery() { return NA; }

		/**
		 * Check if analog buttons/triggers are supported by device.
		 * 
		 * If true, {@link get_analog_inputs} will be used to fill in data. Otherwise,
		 * values from {@link get_base_inputs} are utilized.
		 */
		public virtual bool has_analog_buttons() { return false; }

		/**
		 * Additional transformation to apply to motion data.
		 *
		 * Please note that this should be an option configurable by user. You should
		 * provide reasonable orientation data in NORMAL orientation yourself.
		 */
		public abstract DeviceOrientation orientation { get; set; }

		// Sent only in full response
		public abstract BaseData get_base_inputs();

		/**
		 * Get analog inputs for device.
		 *
		 * Only called if {@link has_analog_buttons} returns true. If it does not,
		 * information from {@link get_base_inputs} is used to fill analog data.
		 */
		public virtual AnalogButtonsData get_analog_inputs() { assert_not_reached(); }

		/**
		 * Get touch data from device.
		 *
		 * @param touch_num Number of touch. Currently, only values 0 and 1 are used,
		 * but this may change in the future.
		 * @return touch information for queried touch number or `null` if not present;
		 */
		public virtual TouchData? get_touch(uint8 touch_num) { return null; }

		/**
		 * Get motion timestamp in microseconds for device.
		 *
		 * Only called if {@link get_device_type} reports that device has motion.
		 *
		 * It generally should not update for gyroscope-only changes.
		 */
		public virtual uint64 get_motion_timestamp() { assert_not_reached(); }

		/**
		 * Get accelerometer data for device in Gs.
		 *
		 * Only called if {@link get_device_type} reports that device has motion.
		 *
		 * Axis directions:
		 *
		 * || ''Name'' || ''Positive direction''                             ||
		 * || x        || Rightwards (-1.0f when laying on the left side)    ||
		 * || y        || Downwards (-1.0f when laying still)                ||
		 * || z        || Forward (-1.0f whith buttons facing away from you) ||
		 */
		public virtual MotionData get_accelerometer() { assert_not_reached(); }

		/**
		 * Get gyroscope data for device in deg/s.
		 *
		 * Only called if {@link get_device_type} reports that device has gyro.
		 *
		 * Axis directions:
		 *
		 * || ''Name'' || ''Description'' || ''Positive direction''                               ||
		 * || x        || Pitch           || Clockwise when viewed from the left (far end rising) ||
		 * || y        || Yaw             || Clockwise when viewed from the top                   ||
		 * || z        || Roll            || Clockwise when viewed from the near end              ||
		 */
		public virtual MotionData get_gyro() { assert_not_reached(); }
	}
}
