(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2022 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

 *****************************************************************************)

(** Dynamic Fdkaac encoder *)

let path =
  try [Sys.getenv "FDKAAC_DYN_PATH"]
  with Not_found ->
    List.fold_left
      (fun l x -> (x ^ "/fdkaac") :: l)
      Configure.findlib_path Configure.findlib_path

open Fdkaac_dynlink

let () =
  let load () =
    match handler.fdkaac_module with
      | Some m ->
          let module Fdkaac = (val m : Fdkaac_dynlink.Fdkaac_t) in
          let module Register = Fdkaac_encoder.Register (Fdkaac) in
          Register.register_encoder "AAC/fdkaac/dynlink"
      | None -> assert false
  in
  Hashtbl.add Dyntools.dynlink_list "fdkaac encoder"
    { Dyntools.path; files = ["fdkaac"; "fdkaac_loader"]; load }
