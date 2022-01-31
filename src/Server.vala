/* Server.vala
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

using Gee;

namespace Cemuhook {
	public errordomain ServerError {
		SERVER_FULL,
		ALREADY_SERVING
	}

	private class ClientRequest : Object, Hashable<ClientRequest> {
		public ClientRequest(uint32 client_id, AbstractPhysicalDevice? dev = null) {
			this.client_id = client_id;
			this.dev = dev;
		}

		public uint32 client_id;
		public weak AbstractPhysicalDevice? dev;

		public bool equal_to(ClientRequest o)
		requires (dev != null) {
			return client_id == o.client_id &&
			       dev == o.dev;
		}

		public uint hash()
		requires (dev != null) {
			return client_id ^ Gee.Functions.get_hash_func_for(typeof(AbstractPhysicalDevice))(dev);
		}
	}

	private class ClientRecord {
		public SocketAddress addr;
		public uint32 client_id;
		public int64 last_request_time;

		public ClientRecord(SocketAddress addr, uint32 client_id) {
			this.addr = addr;
			this.client_id = client_id;
			last_request_time = get_monotonic_time();
		}

		public void update() {
			last_request_time = get_monotonic_time();
		}
	}

	/**
	 * Cemuhook-compliant server implementation
	 *
	 * This is the core part of Cemuhook provider application. It handles most
	 * of logic, such as accepting connections and sending reports about devices.
	 *
	 * For server to work, you *must* run main loop, either directly or via one of many
	 * existing wrappers.
	 */
	public class Server: Object, Initable {
		[Description(nick = "UDP port to use", blurb = "Server will accept connections on this port")]
		public uint16 port { get; construct; default = 26760; }
		public weak MainContext? context { get; construct; default = null; }

		private Socket sock;
		private uint32 server_id;
		private uint8 input_buffer[2048];

		private Utils.SourceGuard socket_source_guard;
		private Utils.SourceGuard cleanup_source_guard;

		private ArrayList<AbstractPhysicalDevice> devices;

		private HashMap<ClientRequest, ClientRecord> clients_map;
		private HashMultiMap<weak AbstractPhysicalDevice, ClientRecord> device_to_client_map;
		private HashMultiMap<uint32, weak AbstractPhysicalDevice> client_to_device_map;
		private HashMap<uint32, uint32> client_packet_counters;

		private HashMultiMap<weak AbstractPhysicalDevice, ulong> device_signals_map;

		construct {
			server_id = Random.next_int();
			devices = new ArrayList<AbstractPhysicalDevice>();
			clients_map = new HashMap<ClientRequest, ClientRecord>();
			device_to_client_map = new HashMultiMap<weak AbstractPhysicalDevice, ClientRecord>();
			client_to_device_map = new HashMultiMap<uint32, weak AbstractPhysicalDevice>();
			client_packet_counters = new HashMap<uint32, uint32>();
			device_signals_map = new HashMultiMap<weak AbstractPhysicalDevice, ulong>();
		}

		/**
		 * Set up new server
		 *
		 * @param port UDP port to accept packets on
		 * @param context Main context to use
		 */
		public Server(uint16 port = 26760, MainContext? context = null) throws Error {
			Object(port : port, context : context);
			init();
		}

		public bool init(Cancellable? cancellable = null) throws Error {
			SocketFamily socket_family = IPV4;
			sock = new Socket(socket_family, DATAGRAM, UDP);
			var addr = new InetSocketAddress(new InetAddress.loopback(socket_family), port);
			sock.bind(addr, false);

			// The below code produces vala warnings - THIS IS INTENDED AND KNOWN
			// See https://gitlab.gnome.org/GNOME/vala/-/issues/957#note_1346912

			var socket_source = sock.create_source(IN);
			SocketSourceFunc socket_delegate = handle_incoming_packet;
			socket_source.set_priority(GLib.Priority.HIGH);
			socket_source.set_callback(socket_delegate);
			socket_source.attach(context);
			socket_source_guard = new Utils.SourceGuard(socket_source);

			var cleanup_source = new TimeoutSource.seconds(1);
			SourceFunc cleanup_delegate = cleanup_controllers;
			cleanup_source.set_callback(cleanup_delegate);
			cleanup_source.attach(context);
			cleanup_source_guard = new Utils.SourceGuard(cleanup_source);
			return true;
		}

		~Server() {
			foreach (var dev in devices) {
				dev.removed(this);
			}
		}

		/**
		 * Currently connected devices
		 */
		public uint8 active_devices_count {
			get {
				return (uint8)devices.size;
			}
		}

		/**
		 * Register device to server
		 *
		 * If successful, this will make server advertise device to clients.
		 *
		 * There's no corresponding public method to disconnect device. Use {@link AbstractPhysicalDevice.disconnected} signal
		 * to remove device from all servers it's registered on.
		 */
		public void add_device(AbstractPhysicalDevice dev) throws ServerError {
			if (devices.contains(dev)) {
				throw new ServerError.ALREADY_SERVING("trying to add duplicate device");
			}
			if (devices.size >= SLOTS_PER_SERVER) {
				throw new ServerError.SERVER_FULL("no free server slots");
			}
			devices.add(dev);
			dev.added(this);
			device_signals_map[dev] = dev.disconnected.connect_after(disconnect_device);
			device_signals_map[dev] = dev.updated.connect_after(update_device);
		}

		private void disconnect_device(AbstractPhysicalDevice dev) {
			/*
			 * We don't remove device from clients_map or device_to_client_map here.
			 * This would be a bit tricky to do efficiently and this also is not a problem because:
			 * 1. Those only hold weak references, so device destruction is not delayed.
			 * 2. Device removal cycle will clean those up in 5 seconds or less.
			 *
			 * The only scenario where this may cause issues is rapidly connecting and disconnecting device,
			 * but this is unlikely to happen in practice and even then DoS can be caused by clients
			 * without anything like rapid reconnects going on.
			 *
			 * TODO: send a single packet signalling controller disconnection?
			 */

			/*
			 * Disconnect signals. While this is usually a waste of time, since device gets destroyed anyways,
			 * this prevents potential segfaults if device is added to a few servers at once for whatever reason.
			 * Since nobody likes segfaults, just be safe.
			 */

			foreach (var sig in device_signals_map[dev]) {
				SignalHandler.disconnect(dev, sig);
			}

			device_signals_map.remove_all(dev);

			dev.removed(this);
			devices.remove(dev);
		}

		private bool handle_incoming_packet(Socket socket, IOCondition condition) {
			if (IN in condition) {
				SocketAddress sender;
				while (IN in socket.condition_check(IN)) {
					try {
						ssize_t len = socket.receive_from(out sender, input_buffer);
						if (len < HEADER_LENGTH_FULL) {
							continue;
						}

						unowned var msg = input_buffer[0:len];
						var mem_stream = Utils.CreateInlineMIStream(msg);
						var inp = new DataInputStream(mem_stream);
						inp.byte_order = LITTLE_ENDIAN;

						HeaderData header;
						if (!Utils.parse_header('C', inp, msg, out header)) {
							continue;
						}

						switch (header.type) {
						case VERSION:
							send_version_message(sender);
							break;
						case PORTS:
							var amount = uint32.min(inp.read_uint32(), 5);
							for (int i = 0; i < amount; ++i) {
								send_slot_info_message(sender, inp.read_byte());
							}
							break;
						case DATA:
							var rtype = (RegistrationType)inp.read_byte();
							var slot = inp.read_byte();
							uint64 mac = ((uint64)inp.read_byte() << 40) |
										 ((uint64)inp.read_byte() << 32) |
										 ((uint64)inp.read_byte() << 24) |
										 ((uint64)inp.read_byte() << 16) |
										 ((uint64)inp.read_byte() << 8)  |
										 ((uint64)inp.read_byte() << 0);
							register_controllers_request(header.id, sender, rtype, slot, mac);
							break;
						}
					} catch (Error e) {
						warning(@"Error when processing incoming packet: $(e.message)");
					}
				}
			}

			return Source.CONTINUE;
		}

		private void fill_in_header(DataOutputStream ostr, MessageType message_type, size_t len) throws Error {
			ostr.byte_order = LITTLE_ENDIAN;
			ostr.put_string("DSUS");
			ostr.put_uint16(PROTOCOL_VERSION);
			ostr.put_uint16((uint16)(len - HEADER_LENGTH));
			ostr.put_uint32(0); // CRC32 placeholder
			ostr.put_uint32(server_id);
			ostr.put_uint32((uint32)message_type);
		}

		private void fill_in_crc32(uint8[] msg) {
			uint32 zeroes = 0;
			Memory.copy(&msg[8], &zeroes, sizeof(uint32));
			var crc = ZLib.Utility.crc32(0, msg).to_little_endian();
			Memory.copy(&msg[8], &crc, sizeof(uint32));
		}

		private void send_version_message(SocketAddress addr) throws Error {
			const size_t LEN = HEADER_LENGTH_FULL + 2;
			uint8 outbuf[LEN] = {0};
			{
				var mem_stream = Utils.CreateInlineMOStream(outbuf);
				var ostr = new DataOutputStream(mem_stream);

				fill_in_header(ostr, VERSION, LEN);
				ostr.put_uint16(PROTOCOL_VERSION);
			}
			fill_in_crc32(outbuf);
			sock.send_to(addr, outbuf);
		}

		private void fill_in_controller_header(DataOutputStream ostr, uint8 slot_id) throws Error
		requires (slot_id < SLOTS_PER_SERVER) {
			ostr.put_byte(slot_id);
			if (slot_id < devices.size) {
				var dev = devices[slot_id];
				ostr.put_byte((uint8)SlotState.CONNECTED);
				ostr.put_byte((uint8)dev.get_device_type());
				ostr.put_byte((uint8)dev.get_connection_type());
				{
					// 48-bit number is a pain to work with
					// It's also stored in big-endian manner, go figure
					var mac = dev.get_mac();
					ostr.put_byte((uint8)(mac >> 40));
					ostr.put_byte((uint8)(mac >> 32));
					ostr.put_byte((uint8)(mac >> 24));
					ostr.put_byte((uint8)(mac >> 16));
					ostr.put_byte((uint8)(mac >> 8));
					ostr.put_byte((uint8)(mac >> 0));
				}
				ostr.put_byte((uint8)dev.get_battery());
			}
		}

		private void send_slot_info_message(SocketAddress addr, uint8 slot_id) throws Error
		requires (slot_id < SLOTS_PER_SERVER) {
			const size_t LEN = HEADER_LENGTH_FULL + 12;
			uint8 outbuf[LEN] = {0};
			{
				var mem_stream = Utils.CreateInlineMOStream(outbuf);
				var ostr = new DataOutputStream(mem_stream);

				fill_in_header(ostr, PORTS, LEN);
				fill_in_controller_header(ostr, slot_id);
			}
			fill_in_crc32(outbuf);
			sock.send_to(addr, outbuf);
		}

		private void register_controller(ClientRequest req, SocketAddress addr)
		requires(req.dev != null) {
			ClientRecord record;
			if (!clients_map.has_key(req)) {
				// Initial request - register for sending
				record = new ClientRecord(addr, req.client_id);
				clients_map[req] = record;
				device_to_client_map[(!) req.dev] = record;
				client_to_device_map[req.client_id] = (!) req.dev;
				if (!client_packet_counters.has_key(req.client_id)) {
					client_packet_counters[req.client_id] = 0;
				}
			} else {
				// Follow-up request - just renew request data
				record = clients_map[req];
				record.addr = addr; // Should not be needed, but is not harmful either
				record.update();
			}
		}

		private bool cleanup_controllers() {
			var current_time = get_monotonic_time();
			{
				// Step 1: clean up clients_map, device_to_client_map, client_to_device_map
				var it = clients_map.map_iterator();
				for (var has_next = it.next (); has_next; has_next = it.next ()) {
					var record = it.get_value();
					if ((record.last_request_time + REQUEST_TIMEOUT) < current_time) {
						var request = it.get_key();
						assert(device_to_client_map.remove(request.dev, record));
						assert(client_to_device_map.remove(request.client_id, request.dev));
						it.unset();
					}
				}
			}
			{
				// Step 2: clean up client_packet_counters
				var it = client_packet_counters.map_iterator();
				for (var has_next = it.next (); has_next; has_next = it.next ()) {
					if (!client_to_device_map.contains(it.get_key())) {
						debug("Purging client, id %u", it.get_key());
						it.unset();
					}
				}
			}
			return Source.CONTINUE;
		}

		private void register_controllers_request(uint32 client_id, SocketAddress addr, RegistrationType rtype, uint8 slot, uint64 mac) {
			if (rtype == ALL) {
				foreach (var dev in devices) {
					register_controller(new ClientRequest(client_id, dev), addr);
				}
				return;
			}
			if (SLOT in rtype) {
				if (slot < devices.size) {
					var dev = devices[slot];
					register_controller(new ClientRequest(client_id, dev), addr);
				}
			}
			if (MAC in rtype) {
				if (mac == 0) {
					warning("Requested to register devices with mac = 0. This is a bug in your DSU Client (emulator).");
				}
				foreach (var dev in devices) {
					if (dev.get_mac() == mac) {
						register_controller(new ClientRequest(client_id, dev), addr);
					}
				}
			}
		}

		private MotionData apply_accel_orientation(MotionData accel, DeviceOrientation orientation) {
			switch(orientation) {
				case NORMAL:
					return accel;
				case SIDEWAYS_LEFT:
					return MotionData() {
						x =  accel.z,
						y =  accel.y,
						z = -accel.x
					};
				case SIDEWAYS_RIGHT:
					return MotionData() {
						x = -accel.z,
						y =  accel.y,
						z =  accel.x
					};
				case INVERTED:
					return MotionData() {
						x = -accel.x,
						y =  accel.y,
						z = -accel.z
					};
			}
			assert_not_reached();
		}

		private MotionData apply_gyro_orientation(MotionData gyro, DeviceOrientation orientation) {
			switch(orientation) {
				case NORMAL:
					return gyro;
				case SIDEWAYS_LEFT:
					return MotionData() {
						x = -gyro.z,
						y =  gyro.y,
						z =  gyro.x
					};
				case SIDEWAYS_RIGHT:
					return MotionData() {
						x =  gyro.z,
						y =  gyro.y,
						z = -gyro.x
					};
				case INVERTED:
					return MotionData() {
						x = -gyro.x,
						y =  gyro.y,
						z = -gyro.z
					};
			}
			assert_not_reached();
		}

		private void update_device(AbstractPhysicalDevice dev) {
			const size_t LEN = HEADER_LENGTH_FULL + 80;
			uint8 outbuf[LEN] = {0};

			var slot_id = (uint8)devices.index_of(dev);

			try {
				{
					var mem_stream = Utils.CreateInlineMOStream(outbuf);
					var ostr = new DataOutputStream(mem_stream);

					fill_in_header(ostr, DATA, LEN);
					fill_in_controller_header(ostr, slot_id);

					ostr.put_byte(1); // Connected
					var client_number_pos = ostr.tell();
					assert(client_number_pos == 32);
					ostr.put_uint32(0); // Placeholder for client's packet number

					var base_inputs = dev.get_base_inputs();
					var btns = base_inputs.buttons;
					ostr.put_byte((uint8)((uint16)btns >> 0));
					ostr.put_byte((uint8)((uint16)btns >> 8));
					ostr.put_byte((HOME  in btns) ? 1 : 0); // PS/HOME button
					ostr.put_byte((TOUCH in btns) ? 1 : 0);

					ostr.put_byte(base_inputs.left_x);
					ostr.put_byte(base_inputs.left_y);
					ostr.put_byte(base_inputs.right_x);
					ostr.put_byte(base_inputs.right_y);

					{
						// Generate data from binary inputs
						AnalogButtonsData abdata = AnalogButtonsData() {
							dpad_up =    (UP    in btns ? 255 : 0),
							dpad_down =  (DOWN  in btns ? 255 : 0),
							dpad_left =  (LEFT  in btns ? 255 : 0),
							dpad_right = (RIGHT in btns ? 255 : 0),
							A =          (A     in btns ? 255 : 0),
							B =          (B     in btns ? 255 : 0),
							X =          (X     in btns ? 255 : 0),
							Y =          (Y     in btns ? 255 : 0),
							R1 =         (R1    in btns ? 255 : 0),
							L1 =         (L1    in btns ? 255 : 0),
							R2 =         (R2    in btns ? 255 : 0),
							L2 =         (L2    in btns ? 255 : 0),
						};

						// Fill in hardware data if present
						dev.get_analog_inputs(ref abdata);

						ostr.put_byte(abdata.dpad_left);
						ostr.put_byte(abdata.dpad_down);
						ostr.put_byte(abdata.dpad_right);
						ostr.put_byte(abdata.dpad_up);
						ostr.put_byte(abdata.Y);
						ostr.put_byte(abdata.B);
						ostr.put_byte(abdata.A);
						ostr.put_byte(abdata.X);
						ostr.put_byte(abdata.R1);
						ostr.put_byte(abdata.L1);
						ostr.put_byte(abdata.R2);
						ostr.put_byte(abdata.L2);
					}

					{
						uint8[] touches = {0, 1};
						foreach(var idx in touches) {
							var t = dev.get_touch(idx);
							if (t != null) {
								ostr.put_byte(1);
								ostr.put_byte(((!)t).id);
								ostr.put_uint16(((!)t).x);
								ostr.put_uint16(((!)t).y);
							} else {
								ostr.put_byte(0);
								ostr.put_byte(0);
								ostr.put_uint16(0);
								ostr.put_uint16(0);
							}
						}
					}

					var dev_type = dev.get_device_type();
					if (dev_type == ACCELEROMETER_ONLY || dev_type == GYRO_FULL) {
						ostr.put_uint64(dev.get_motion_timestamp());
						var accel = apply_accel_orientation(dev.get_accelerometer(), dev.orientation);
						Utils.write_float(ostr, accel.x);
						Utils.write_float(ostr, accel.y);
						Utils.write_float(ostr, accel.z);
					} else {
						ostr.put_uint64(0);
						Utils.write_float(ostr, 0);
						Utils.write_float(ostr, 0);
						Utils.write_float(ostr, 0);
					}

					if (dev_type == GYRO_FULL) {
						var gyro = apply_gyro_orientation(dev.get_gyro(), dev.orientation);
						Utils.write_float(ostr, gyro.x);
						Utils.write_float(ostr, gyro.y);
						Utils.write_float(ostr, gyro.z);
					} else {
						Utils.write_float(ostr, 0);
						Utils.write_float(ostr, 0);
						Utils.write_float(ostr, 0);
					}

					ostr.flush();

					foreach (var record in device_to_client_map[dev]) {
						var packet_num = client_packet_counters[record.client_id];
						client_packet_counters[record.client_id] = packet_num + 1;

						ostr.seek(client_number_pos, SET);
						ostr.put_uint32(packet_num);
						ostr.flush();

						fill_in_crc32(outbuf);
						sock.send_to(record.addr, outbuf);
					}
				}
			} catch (Error e) {
				warning(@"Error when sending data packet: $(e.message)");
			}
		}
	}
}
