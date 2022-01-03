/* Utils.vala
 *
 * Copyright 2022 v1993 <v19930312@gmail.co,>
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

namespace Cemuhook.Utils {
	// See https://gitlab.gnome.org/GNOME/vala/-/issues/1271 why not use usual constructor
	internal MemoryOutputStream CreateInlineMOStream(uint8[] data) {
		return (MemoryOutputStream)
			Object.new(typeof(MemoryOutputStream),
			"data", data,
			"size", data.length,
			"realloc-function", null,
			"destroy-function", null
		);
	}

	// Note: currently, constructor takes ownership of data. This results in needless copy.
	// This function should be rewritten once that is fixed. For now, future-proof by doing an explicit copy (to avoid double-free once issue is fixed GLib-side).
	internal MemoryInputStream CreateInlineMIStream(uint8[] data) {
		uint8[] data_copy = data.copy();
		return new MemoryInputStream.from_data((owned)data_copy);
	}

	// There might be a way to do this without introducing additional class
	// Remove this if there indeed is one
	internal class SourceGuard : Object {
		public Source source { get; construct; }

		public SourceGuard(Source source) {
			Object(source: source);
		}
		~SourceGuard() {
			source.destroy();
		}
	}

	internal void write_float(DataOutputStream ostr, float flt) throws Error {
		assert(sizeof(float) == sizeof(uint32));
		uint32 target = 0;
		Memory.copy(&target, &flt, sizeof(float));
		// Note: this applies endianness switch if you happen to run on big-endian machine
		ostr.put_uint32(target);
	}

	// Helper debugging function
	internal void hexdump (uint8[] data) {
		var builder = new StringBuilder.sized (16);
		var i = 0;

		foreach (var c in data) {
			if (i % 16 == 0) {
				print ("%08x | ", i);
			}
			i++;
			print ("%02x ", c);
			if (((char) c).isprint ()) {
				builder.append_c ((char) c);
			} else {
				builder.append (".");
			}
			if (i % 16 == 0) {
				print ("| %s\n", builder.str);
				builder.erase ();
			}
		}

		if (i % 16 != 0) {
			print ("%s| %s\n", string.nfill ((16 - (i % 16)) * 3, ' '), builder.str);
		}
	}
}
