(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
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

(*
 * Copyright (c) 2012 Citrix Systems, Inc.
 *)

(** Functions relating to memory requirements of Xen domains *)

open Printf

module D = Debug.Debugger(struct let name = "xenops" end)
open D

let ( +++ ) = Int64.add
let ( --- ) = Int64.sub
let ( *** ) = Int64.mul
let ( /// ) = Int64.div

(* === Memory conversion factors ============================================ *)

let bytes_per_kib  = 1024L
let bytes_per_mib  = 1048576L
let bytes_per_page = Int64.of_int (Mmap.getpagesize ())
let kib_per_page   = bytes_per_page /// bytes_per_kib
let kib_per_mib    = 1024L
let pages_per_mib  = bytes_per_mib /// bytes_per_page

(* === Arithmetic functions ================================================= *)

(** Returns true if (and only if) the specified argument is a power of 2. *)
let is_power_of_2 n =
	(n > 0) && (n land (0 - n) = n)

let round_down_to_multiple_of x y =
	(x /// y) *** y

let round_up_to_multiple_of x y =
	((x +++ y --- 1L) /// y) *** y

(* === Memory rounding functions ============================================ *)

let round_up = round_up_to_multiple_of
let round_down = round_down_to_multiple_of

let round_bytes_down_to_nearest_page_boundary v = round_down v bytes_per_page
let round_bytes_down_to_nearest_mib           v = round_down v bytes_per_mib
let round_kib_down_to_nearest_page_boundary   v = round_down v kib_per_page
let round_kib_up_to_nearest_page_boundary     v = round_up   v kib_per_page
let round_kib_up_to_nearest_mib               v = round_up   v kib_per_mib
let round_pages_up_to_nearest_mib             v = round_up   v pages_per_mib

(* === Division functions =================================================== *)

let divide_rounding_down numerator denominator =
	numerator /// denominator

let divide_rounding_up numerator denominator =
	(numerator +++ denominator --- 1L) /// denominator

(* === Memory unit conversion functions ===================================== *)

let bytes_of_kib   value = value *** bytes_per_kib
let bytes_of_pages value = value *** bytes_per_page
let bytes_of_mib   value = value *** bytes_per_mib
let kib_of_mib     value = value *** kib_per_mib
let kib_of_pages   value = value *** kib_per_page
let pages_of_mib   value = value *** pages_per_mib

let kib_of_bytes_free   value = divide_rounding_down value bytes_per_kib
let pages_of_bytes_free value = divide_rounding_down value bytes_per_page
let pages_of_kib_free   value = divide_rounding_down value kib_per_page
let mib_of_bytes_free   value = divide_rounding_down value bytes_per_mib
let mib_of_kib_free     value = divide_rounding_down value kib_per_mib
let mib_of_pages_free   value = divide_rounding_down value pages_per_mib

let kib_of_bytes_used   value = divide_rounding_up value bytes_per_kib
let pages_of_bytes_used value = divide_rounding_up value bytes_per_page
let pages_of_kib_used   value = divide_rounding_up value kib_per_page
let mib_of_bytes_used   value = divide_rounding_up value bytes_per_mib
let mib_of_kib_used     value = divide_rounding_up value kib_per_mib
let mib_of_pages_used   value = divide_rounding_up value pages_per_mib

(* === Host memory properties =============================================== *)

let get_free_memory_kib ~xc =
	kib_of_pages (Int64.of_nativeint (Xc.physinfo xc).Xc.free_pages)
let get_scrub_memory_kib ~xc =
	kib_of_pages (Int64.of_nativeint (Xc.physinfo xc).Xc.scrub_pages)
let get_total_memory_mib ~xc =
	mib_of_pages_free (Int64.of_nativeint ((Xc.physinfo xc).Xc.total_pages))
let get_total_memory_bytes ~xc =
	bytes_of_pages (Int64.of_nativeint ((Xc.physinfo xc).Xc.total_pages))

(* === Domain memory breakdown ============================================== *)

(*           ╤  ╔══════════╗                                     ╤            *)
(*           │  ║ shadow   ║                                     │            *)
(*           │  ╠══════════╣                                     │            *)
(*  overhead │  ║ extra    ║                                     │            *)
(*           │  ║ external ║                                     │            *)
(*           │  ╠══════════╣                          ╤          │            *)
(*           │  ║ extra    ║                          │          │            *)
(*           │  ║ internal ║                          │          │            *)
(*           ╪  ╠══════════╣                ╤         │          │ footprint  *)
(*           │  ║ video    ║                │         │          │            *)
(*           │  ╠══════════╣  ╤    ╤        │ actual  │ xen      │            *)
(*           │  ║          ║  │    │        │ /       │ maximum  │            *)
(*           │  ║          ║  │    │        │ target  │          │            *)
(*           │  ║ guest    ║  │    │ build  │ /       │          │            *)
(*           │  ║          ║  │    │ start  │ total   │          │            *)
(*    static │  ║          ║  │    │        │         │          │            *)
(*   maximum │  ╟──────────╢  │    ╧        ╧         ╧          ╧            *)
(*           │  ║          ║  │                                               *)
(*           │  ║          ║  │                                               *)
(*           │  ║ balloon  ║  │ build                                         *)
(*           │  ║          ║  │ maximum                                       *)
(*           │  ║          ║  │                                               *)
(*           ╧  ╚══════════╝  ╧                                               *)

(* === Domain memory breakdown: HVM guests ================================== *)

module type MEMORY_MODEL_DATA = sig
	val extra_internal_mib : int64
	val extra_external_mib : int64
end

module HVM_memory_model_data : MEMORY_MODEL_DATA = struct
	let extra_internal_mib = 1L
	let extra_external_mib = 1L
end

module Linux_memory_model_data : MEMORY_MODEL_DATA = struct
	let extra_internal_mib = 0L
	let extra_external_mib = 1L
end

module Memory_model (D : MEMORY_MODEL_DATA) = struct

	let build_max_mib video_mib static_max_mib = static_max_mib --- video_mib

	let build_start_mib video_mib target_mib = target_mib --- video_mib

	let xen_max_offset_mib = D.extra_internal_mib

	let xen_max_mib target_mib = target_mib +++ xen_max_offset_mib

	let shadow_mib static_max_mib vcpu_count multiplier =
		let vcpu_pages = 256L *** (Int64.of_int vcpu_count) in
		let p2m_map_pages = static_max_mib in
		let shadow_resident_pages = static_max_mib in
		let total_mib = mib_of_pages_used
			(vcpu_pages +++ p2m_map_pages +++ shadow_resident_pages) in
		let total_mib_multiplied =
			Int64.of_float ((Int64.to_float total_mib) *. multiplier) in
		max 1L total_mib_multiplied

	let overhead_mib static_max_mib vcpu_count multiplier =
		D.extra_internal_mib +++
		D.extra_external_mib +++
		(shadow_mib static_max_mib vcpu_count multiplier)

	let footprint_mib target_mib static_max_mib vcpu_count multiplier =
		target_mib +++ (overhead_mib static_max_mib vcpu_count multiplier)

	let round_shadow_multiplier static_max_mib vcpu_count
			requested_multiplier domid =
		let shadow_mib = shadow_mib static_max_mib vcpu_count in
		let requested_shadow_mib = shadow_mib requested_multiplier in
		let default_shadow_mib = shadow_mib 1. in
		Xc.with_intf (fun xc ->
			let actual_shadow_mib =
				Int64.of_int (Xc.shadow_allocation_get xc domid) in
			let actual_multiplier =
				(Int64.to_float actual_shadow_mib) /.
				(Int64.to_float default_shadow_mib) in
			debug
				"actual shadow value is %Ld MiB [multiplier = %0.2f]; \
				requested value was %Ld MiB [multiplier = %.2f]"
				actual_shadow_mib actual_multiplier
				requested_shadow_mib requested_multiplier;
				(* Inevitably due to rounding the actual multiplier may   *)
				(* be different from the supplied value. However if the   *)
				(* supplied value was accepted then we record that value. *)
				(* If Xen overrode us then we record the actual value.    *)
			if actual_shadow_mib <> requested_shadow_mib
			then actual_multiplier
			else requested_multiplier
		)

	let shadow_multiplier_default = 1.0

end

module HVM = Memory_model (HVM_memory_model_data)
module Linux = Memory_model (Linux_memory_model_data)

(* === Miscellaneous functions ============================================== *)

(** @deprecated Use [memory_check.vm_compute_start_memory] instead. *)
let required_to_boot_kib hvm vcpus mem_kib mem_target_kib shadow_multiplier =
	let max_mib = mib_of_kib_used mem_kib in
	let target_mib = mib_of_kib_used mem_target_kib in
	kib_of_mib (
		(if hvm
		 then HVM.footprint_mib 
		 else Linux.footprint_mib)
			target_mib max_mib vcpus shadow_multiplier)

let wait_xen_free_mem ~xc ?(maximum_wait_time_seconds=64) required_memory_kib =
	let rec wait accumulated_wait_time_seconds =
		let host_info = Xc.physinfo xc in
		let free_memory_kib =
			kib_of_pages (Int64.of_nativeint host_info.Xc.free_pages) in
		let scrub_memory_kib =
			kib_of_pages (Int64.of_nativeint host_info.Xc.scrub_pages) in
		(* At exponentially increasing intervals, write  *)
		(* a debug message saying how long we've waited: *)
		if is_power_of_2 accumulated_wait_time_seconds then debug
			"Waited %i second(s) for memory to become available: \
			%Ld KiB free, %Ld KiB scrub, %Ld KiB required"
			accumulated_wait_time_seconds
			free_memory_kib scrub_memory_kib required_memory_kib;
		if free_memory_kib >= required_memory_kib
			(* We already have enough memory. *)
			then true else
		if scrub_memory_kib = 0L
			(* We'll never have enough memory. *)
			then false else
		if accumulated_wait_time_seconds >= maximum_wait_time_seconds
			(* We've waited long enough. *)
			then false else
		begin
			Unix.sleep 1;
			wait (accumulated_wait_time_seconds + 1)
		end in
	wait 0
