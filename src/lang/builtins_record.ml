(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2011 Savonet team

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
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

  (** Functions operating on extensible records. *)

open Lang_builtins

let () = 
  let row = Lang.univ_t 1 in
  let e = Lang_types.Fields.empty in
  add_builtin "record.labels" ~cat:Liq
    ~descr:"Get the list of defined labels of a record."
   ["",Lang.record_t ~row e,None,None] (Lang.list_t Lang.string_t)
   (fun p ->
     let l = Lang.to_record (List.assoc "" p) in
     let l = Lang_types.list_of_fields l in
     let l = List.map fst l in
     let l = List.map Lang.string l in
     Lang.list ~t:Lang.string_t l)

let () =
  let opt_row = Lang.univ_t 1 in
  Lang.add_builtin_base "record.empty" 
    ~category:(string_of_category Liq)
    ~descr:"An empty record."
    (Lang.Record Lang_types.Fields.empty) 
    (Lang.record_t ~opt_row Lang_types.Fields.empty)
