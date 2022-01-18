/* WrapperPhysicalDevice.vala
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
	 * Class intended to allow wrapping other physical devices.
	 *
	 * It should be used as a base for other classes that modify the reslt of other devices,
	 * e.g. changing their orientation in space.
	 *
	 * By default, all methods simply call those of wrapped device.
	 * Signals are also automatically connected.
	 *
	 * While all methods are already implemented, this class is declared abstract to prevent
	 * using it accidentally. If you're absolutely positive you actually need its functionality
	 * without transformations, just make a subclass only declaring a constructor.
	 */
	public abstract class WrapperPhysicalDevice : Object, AbstractPhysicalDevice {
		public AbstractPhysicalDevice wrapped_device { get; construct; }

		private void call_disconnected() {
			disconnected();
		}

		private void call_updated() {
			updated();
		}

		construct {
			wrapped_device.disconnected.connect(call_disconnected);
			wrapped_device.updated.connect(call_updated);
		}

		protected WrapperPhysicalDevice(AbstractPhysicalDevice dev) {
			Object(wrapped_device : dev);
		}

		public DeviceType get_device_type() { return wrapped_device.get_device_type(); }
		public ConnectionType get_connection_type() { return wrapped_device.get_connection_type(); }
		public uint64 get_mac() { return wrapped_device.get_mac(); }
		public BatteryStatus get_battery() { return wrapped_device.get_battery(); }
		public bool has_analog_buttons() { return wrapped_device.has_analog_buttons(); }
		public DeviceOrientation orientation {
			get {
				return wrapped_device.orientation;
			}
			set {
				wrapped_device.orientation = value;
			}
		}
		public BaseData get_base_inputs() { return wrapped_device.get_base_inputs(); }
		public AnalogButtonsData get_analog_inputs() { return wrapped_device.get_analog_inputs(); }
		public TouchData? get_touch(uint8 touch_num) { return wrapped_device.get_touch(touch_num); }
		public MotionData get_accelerometer() { return wrapped_device.get_accelerometer(); }
		public MotionData get_gyro() { return wrapped_device.get_gyro(); }
	 }
}
