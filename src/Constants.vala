/* Constants.vala
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
	internal const size_t HEADER_LENGTH = 16;
	internal const size_t HEADER_LENGTH_FULL = 20;
	internal const uint16 PROTOCOL_VERSION = 1001;
	internal const int64 REQUEST_TIMEOUT = 5000000;
	public const size_t SLOTS_PER_SERVER = 4;

	public const uint8 STICK_NEUTRAL = 127;

	internal enum MessageType {
		VERSION = 0x100000,
		PORTS = 0x100001,
		DATA = 0x100002,

		// Rumble extension
		EXT_RUMBLE_INFO = 0x110001,
		EXT_RUMBLE_SET = 0x110002
	}

	[SimpleType]
	internal struct HeaderData {
		uint32 id;
		MessageType type;
	}

	internal enum SlotState {
		NOT_CONNECTED,
		RESERVED,
		CONNECTED
	}

	public enum DeviceType {
		NO_MOTION,
		ACCELEROMETER_ONLY,
		GYRO_FULL
	}

	public enum ConnectionType {
		OTHER,
		USB,
		BLUETOOTH
	}

	[Flags]
	public enum RegistrationType {
		ALL = 0,
		SLOT,
		MAC
	}

	public enum BatteryStatus {
		NA =       0x00,
		DYING =    0x01,
		LOW =      0x02,
		MEDIUM =   0x03,
		HIGH =     0x04,
		FULL =     0x05,
		CHARGING = 0xEE,
		CHARGED =  0xEF
	}

	public enum DeviceOrientation {
		NORMAL, ///< No changes are applied
		SIDEWAYS_LEFT, ///< Example: using sideways left joycon or wiimote
		SIDEWAYS_RIGHT, ///< Example: using sideways right joycon
		INVERTED; ///< Example: using sideways left joycon when game expects sideways right joycon

		public string to_string() {
			EnumClass enumc = (EnumClass)typeof(DeviceOrientation).class_ref();
			unowned EnumValue? eval = enumc.get_value (this);
			return_val_if_fail(eval != null, null);
			return eval.value_nick;
		}

		public static bool try_parse(string nick, out DeviceOrientation res) {
			EnumClass enumc = (EnumClass)typeof(DeviceOrientation).class_ref();
			unowned EnumValue? eval = enumc.get_value_by_nick(nick);
			if (eval == null) {
				res = NORMAL;
				return false;
			}

			res = (DeviceOrientation)eval.value;
			return true;
		}
	}

	// Ordered as such to match packet order
	[Flags]
	public enum Buttons {
		// First byte
		SHARE,
		L3,
		R3,
		OPTIONS,
		UP,
		RIGHT,
		DOWN,
		LEFT,

		// Second byte
		L2,
		R2,
		L1,
		R1,
		X,
		A,
		B,
		Y,

		// Occupy separate bytes
		HOME,
		TOUCH
	}

	[SimpleType]
	public struct BaseData {
		Buttons buttons;

		uint8 left_x;
		uint8 left_y;
		uint8 right_x;
		uint8 right_y;
	}

	[SimpleType]
	public struct AnalogButtonsData {
		uint8 dpad_up;
		uint8 dpad_down;
		uint8 dpad_left;
		uint8 dpad_right;
		uint8 A;
		uint8 B;
		uint8 X;
		uint8 Y;
		uint8 R1;
		uint8 L1;
		uint8 R2;
		uint8 L2;
	}

	[SimpleType]
	public struct TouchData {
		uint8 id;
		uint16 x;
		uint16 y;
	}

	[SimpleType]
	public struct MotionData {
		float x;
		float y;
		float z;
	}
}
