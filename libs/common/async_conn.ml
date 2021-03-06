(*
 * Copyright (C) 2009      Citrix Ltd.
 * Author Prashanth Mundkur <firstname.lastname@citrix.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)


let verbose = ref false

let dbg fmt =
	let logger s = if !verbose then Printf.printf "%s\n%!" s in
	Printf.ksprintf logger fmt

type t =
{
	ev_loop : Eventloop.t;
  	ev_handle : Eventloop.handle;
	ev_fd : Unix.file_descr;

	mutable callbacks : callbacks;
	mutable send_done_enabled : bool;

	mutable send_buf : Bigbuffer.t;
}

and callbacks =
{
	connect_callback : t -> unit;
	recv_callback : t -> string -> (* offset *) int -> (* length *) int -> unit;
	send_done_callback : t -> unit;
	shutdown_callback : t -> unit;
	error_callback : t -> Eventloop.error -> unit;
}

let compare t1 t2 = compare t1.ev_handle t2.ev_handle
let hash t = Eventloop.handle_hash t.ev_handle

module Conns = Connection_table.Make(struct type conn = t end)

let accept_callback el h fd addr =
	failwith "Async_conn.accept_callback: invalid use"

let connect_callback el h =
	let conn = Conns.get_conn h in
	conn.callbacks.connect_callback conn

let recv_ready_callback el h fd =
	let conn = Conns.get_conn h in
	let buflen = 512 in
	let buf = String.create buflen in
	try
		let read_bytes = Unix.read fd buf 0 buflen in
		if read_bytes = 0 then
			conn.callbacks.shutdown_callback conn
		else begin
			dbg "<- %s" (String.sub buf 0 read_bytes);
			conn.callbacks.recv_callback conn buf 0 read_bytes
		end
	with
	| Unix.Unix_error (Unix.EWOULDBLOCK, _, _)
	| Unix.Unix_error (Unix.EAGAIN, _, _)
	| Unix.Unix_error (Unix.EINTR, _, _) ->
		()
	| Unix.Unix_error (ec, f, s) ->
		conn.callbacks.error_callback conn (ec, f, s)

let send_ready_callback el h fd =
	let conn = Conns.get_conn h in
	(match Bigbuffer.head conn.send_buf with
	| None -> ()
	| Some payload ->
		  let payload_len = String.length payload in
		  (try
			   (match Unix.write fd payload 0 payload_len with
			    | 0 -> ()
			    | sent ->
				      (* cut out 'sent' bytes out of conn.send_buf *)
				      let buf' = Bigbuffer.make () in
				      let newlen = Int64.sub (Bigbuffer.length conn.send_buf) (Int64.of_int sent) in
				      Bigbuffer.append_bigbuffer buf' conn.send_buf (Int64.of_int sent) newlen;
				      conn.send_buf <- buf'
			   );
			   
		   with
		   | Unix.Unix_error (Unix.EWOULDBLOCK, _, _)
		   | Unix.Unix_error (Unix.EAGAIN, _, _)
		   | Unix.Unix_error (Unix.EINTR, _, _) ->
			     ()
		   | Unix.Unix_error (ec, f, s) ->
			     conn.callbacks.error_callback conn (ec, f, s)
		  ));

	(* We may need to invoke the send_done_callback, but we may
	   have dispatched an error_callback above.  So we need to ensure
	   the connection is still active.
	*)
	if Conns.has_conn h && Bigbuffer.length conn.send_buf = Int64.zero then begin
		Eventloop.disable_send conn.ev_loop conn.ev_handle;
		if conn.send_done_enabled then
			conn.callbacks.send_done_callback conn
	end

let error_callback el h err =
	let conn = Conns.get_conn h in
	conn.callbacks.error_callback conn err

let conn_callbacks =
{
	Eventloop.accept_callback = accept_callback;
	Eventloop.connect_callback = connect_callback;
	Eventloop.error_callback = error_callback;
	Eventloop.recv_ready_callback = recv_ready_callback;
	Eventloop.send_ready_callback = send_ready_callback;
}

let attach ev_loop fd  ?(enable_send_done=false) ?(enable_recv=true) callbacks =
	let ev_handle = Eventloop.register_conn ev_loop fd ~enable_send:false ~enable_recv conn_callbacks in
	let conn = { ev_loop = ev_loop;
		     ev_handle = ev_handle;
		     ev_fd = fd;
		     callbacks = callbacks;
		     send_done_enabled = enable_send_done;
		     send_buf = Bigbuffer.make ();
		   }
	in
	Conns.add_conn ev_handle conn;
	conn

let detach conn =
	Eventloop.remove_conn conn.ev_loop conn.ev_handle;
	Conns.remove_conn conn.ev_handle

let close conn =
	(* It might already be detached; ignore this case. *)
	(try detach conn with _ -> ());
	(try Unix.close conn.ev_fd with _ -> ())

let enable_send_done conn =
	conn.send_done_enabled <- true

let disable_send_done conn =
	conn.send_done_enabled <- false

let enable_recv conn =
	Eventloop.enable_recv conn.ev_loop conn.ev_handle

let disable_recv conn =
	Eventloop.disable_recv conn.ev_loop conn.ev_handle

let connect conn addr =
	Eventloop.connect conn.ev_loop conn.ev_handle addr

let send conn s =
	Bigbuffer.append_substring conn.send_buf s 0 (String.length s);
	Eventloop.enable_send conn.ev_loop conn.ev_handle

let has_pending_send conn =
	Bigbuffer.length conn.send_buf > Int64.zero

let set_callbacks conn callbacks =
	conn.callbacks <- callbacks

let get_handle conn = conn.ev_handle
let get_eventloop conn = conn.ev_loop
let get_fd conn = conn.ev_fd
