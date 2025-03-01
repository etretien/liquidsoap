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

(* Force locale to C *)
external force_locale : unit -> unit = "liquidsoap_set_locale" [@@noalloc]

(** Get page size. *)
external pagesize : unit -> int = "liquidsoap_get_pagesize"
  [@@noalloc]

let pagesize = pagesize ()

(** General configuration *)
let conf = Dtools.Conf.void "Liquidsoap configuration"

let () = force_locale ()

(* Resolve a path. *)
let resolve_path ?cwd path =
  let cwd = match cwd with None -> Sys.getcwd () | Some cwd -> cwd in
  if Filename.is_relative path then Filename.concat cwd path else path

(* Getenv with default value. *)
let getenv ~default value = try Sys.getenv value with Not_found -> default

(* Getenv with option result. *)
let getenv_opt value = try Some (Sys.getenv value) with Not_found -> None

(* Several list utilities *)

let rec prefix p l =
  match (p, l) with
    | [], _ -> true
    | _, [] -> false
    | hp :: tp, hl :: tl -> hp = hl && prefix tp tl

let hashtbl_of_list l =
  let h = Hashtbl.create (List.length l) in
  List.iter (fun (k, v) -> Hashtbl.add h k v) l;
  h

let list_of_metadata m =
  let f x y l = (x, y) :: l in
  Hashtbl.fold f m []

let hashtbl_get : ('a, 'b) Hashtbl.t -> 'a -> 'b option =
 fun h k -> try Some (Hashtbl.find h k) with Not_found -> None

(** Remove the first element satisfying a predicate, raising Not_found
  * if none is found. *)
let remove_one f l =
  let rec aux acc = function
    | [] -> raise Not_found
    | x :: l -> if f x then List.rev_append acc l else aux (x :: acc) l
  in
  aux [] l

(* Read all data from a given filename.
 * We cannot use really_input with the 
 * reported length of the file because
 * some OSes such as windows may do implicit
 * conversions (file opened in text mode in 
 * win32), thus making the actual number of 
 * characters that can be read from the file
 * different than its reported length.. *)
let read_all filename =
  let channel = open_in filename in
  let tmp = Bytes.create pagesize in
  let contents = Strings.Mutable.empty () in
  let rec read () =
    let ret = input channel tmp 0 pagesize in
    if ret > 0 then (
      Strings.Mutable.add_subbytes contents tmp 0 ret;
      read ())
  in
  read ();
  close_in channel;
  Strings.Mutable.to_string contents

(* Drop the first [len] bytes. *)
let buffer_drop buffer len =
  let size = Buffer.length buffer in
  assert (len <= size);
  if len = size then Buffer.clear buffer
  else (
    let tmp = Buffer.sub buffer len (size - len) in
    Buffer.clear buffer;
    Buffer.add_string buffer tmp)

let unix_translator = function
  | Unix.Unix_error (code, name, param) ->
      Some (Printf.sprintf "%s in %s(%s)" (Unix.error_message code) name param)
  | _ -> None

let () = Printexc.register_printer unix_translator

(** Perfect Fisher-Yates shuffle
  * (http://www.nist.gov/dads/HTML/fisherYatesShuffle.html). *)
let randomize a =
  let permute i j =
    let tmp = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- tmp
  in
  let l = Array.length a in
  if l >= 2 then
    for i = 0 to l - 2 do
      permute i (i + Random.int (l - i))
    done

(* Generic escaping function. Returns a list of escaping substitutions. *)
let escape ~special_char ~next ~escape_char s =
  let orig_len = String.length s in
  let rec f (segments, total_len) pos =
    let next_pos = next s (pos : int) in
    let len = next_pos - pos in
    let ret =
      if special_char s pos len then (
        let s = escape_char s pos len in
        let len = String.length s in
        (`Subst (s, len) :: segments, total_len + len))
      else
        ( (match segments with
            | `Orig (pos, s_len) :: segments ->
                `Orig (pos, s_len + len) :: segments
            | segments -> `Orig (pos, len) :: segments),
          total_len + len )
    in
    if next_pos < orig_len then f ret next_pos else ret
  in
  if orig_len > 0 then f ([], 0) 0 else ([], 0)

let utf8_next s i =
  match s.[i] with
    | '\000' .. '\127' -> i + 1
    | '\192' .. '\223' -> i + 2
    | '\224' .. '\239' -> i + 3
    | '\240' .. '\247' -> i + 4
    | _ -> failwith "invalid utf8"

(* Return the utf8 char code of the first utf8 character in the given
   string. *)
let utf8_char_code s pos len =
  if len < 1 then failwith "invalid utf8";
  match s.[pos] with
    | '\000' .. '\127' as c -> Char.code c
    | '\192' .. '\223' as c ->
        if len < 2 then failwith "invalid utf8";
        let n1 = Char.code c in
        let n2 = Char.code s.[pos + 1] in
        if n2 lsr 6 != 0b10 then failwith "invalid utf8";
        ((n1 land 0x1f) lsl 6) lor (n2 land 0x3f)
    | '\224' .. '\239' as c ->
        if len < 3 then failwith "invalid utf8";
        let n1 = Char.code c in
        let n2 = Char.code s.[pos + 1] in
        let n3 = Char.code s.[pos + 2] in
        if n2 lsr 6 != 0b10 || n3 lsr 6 != 0b10 then failwith "invalid utf8";
        let p =
          ((n1 land 0x0f) lsl 12) lor ((n2 land 0x3f) lsl 6) lor (n3 land 0x3f)
        in
        if p >= 0xd800 && p <= 0xdf00 then failwith "invalid utf8";
        p
    | '\240' .. '\247' as c ->
        if len < 4 then failwith "invalid utf8";
        let n1 = Char.code c in
        let n2 = Char.code s.[pos + 1] in
        let n3 = Char.code s.[pos + 2] in
        let n4 = Char.code s.[pos + 3] in
        if n2 lsr 6 != 0b10 || n3 lsr 6 != 0b10 || n4 lsr 6 != 0b10 then
          failwith "invalid utf8";
        ((n1 land 0x07) lsl 18)
        lor ((n2 land 0x3f) lsl 12)
        lor ((n3 land 0x3f) lsl 6)
        lor (n4 land 0x3f)
    | _ -> failwith "invalid utf8"

(* End of Extlib code *)

let ascii_special_char s pos len =
  match (s.[pos], len) with
    | '\'', 1
    | '"', 1
    | '\\', 1
    (* DEL *)
    | '\x7F', 1 ->
        true
    (* Control chars *)
    | c, 1 when Char.code c <= 0x1F -> true
    | c, 1 when Char.code c > 0x7E -> true
    | _ -> false

let utf8_special_char s ofs len = len = 1 && ascii_special_char s ofs len
let ascii_next _ i = i + 1

let escape_char ~escape_fun s pos len =
  match (s.[pos], len) with
    | '\b', 1 -> "\\b"
    | '\n', 1 -> "\\n"
    | '\r', 1 -> "\\r"
    | '\t', 1 -> "\\t"
    | '\\', 1 -> "\\\\"
    | '"', 1 -> "\\\""
    | '\'', 1 -> "\\'"
    | _ -> escape_fun s pos len

let escape_utf8_char =
  let utf8_char_code s pos len =
    try utf8_char_code s pos len with _ -> Uchar.to_int Uchar.rep
  in
  escape_char ~escape_fun:(fun s pos len ->
      Printf.sprintf "\\u%04X" (utf8_char_code s pos len))

let escape_utf8_formatter ?(special_char = utf8_special_char) =
  escape ~special_char ~escape_char:escape_utf8_char ~next:utf8_next

let escape_hex_char =
  escape_char ~escape_fun:(fun s pos len ->
      assert (len = 1);
      Printf.sprintf "\\x%02X" (int_of_char s.[pos]))

let escape_octal_char =
  escape_char ~escape_fun:(fun s pos len ->
      assert (len = 1);
      Printf.sprintf "\\%03o" (int_of_char s.[pos]))

(* We use the \xhh syntax to make sure the resulting string is also consistently readable in
   OCaml. \nnn can be tricky since they are octal sequences in liquidsoap and digital sequences
   in OCaml. *)
let escape_ascii_formatter ?(special_char = ascii_special_char) =
  escape ~special_char ~escape_char:escape_hex_char ~next:ascii_next

let has_subst = List.exists (function `Subst _ -> true | _ -> false)

let escape_string escape s =
  let segments, len = escape s in
  if not (has_subst segments) then s
  else (
    let b = Bytes.create len in
    ignore
      (List.fold_left
         (fun b_pos segment ->
           match segment with
             | `Orig (s_pos, len) ->
                 let b_pos = b_pos - len in
                 Bytes.blit_string s s_pos b b_pos len;
                 b_pos
             | `Subst (subst, len) ->
                 let b_pos = b_pos - len in
                 Bytes.blit_string subst 0 b b_pos len;
                 b_pos)
         len segments);
    Bytes.unsafe_to_string b)

let escape_utf8_string ?special_char =
  escape_string (escape_utf8_formatter ?special_char)

let escape_ascii_string ?special_char =
  escape_string (escape_ascii_formatter ?special_char)

let quote_utf8_string s =
  Printf.sprintf "\"%s\""
    (escape_utf8_string
       ~special_char:(fun s pos len ->
         if s.[pos] = '\'' && len = 1 then false
         else utf8_special_char s pos len)
       s)

let quote_ascii_string s =
  Printf.sprintf "\"%s\""
    (escape_ascii_string
       ~special_char:(fun s pos len ->
         if s.[pos] = '\'' && len = 1 then false
         else ascii_special_char s pos len)
       s)

let quote_string s = try quote_utf8_string s with _ -> quote_ascii_string s
let unescape_utf8_pattern = "\\\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]"
let unescape_hex_pattern = "\\\\x[0-9a-fA-F][0-9a-fA-F]"
let unescape_octal_pattern = "\\\\[0-9][0-9][0-9]"

let unescape_patterns =
  [
    "\\\\a";
    "\\\\b";
    "\\\\e";
    "\\\\f";
    "\\\\n";
    "\\\\r";
    "\\\\t";
    "\\\\v";
    "\\\\/";
    "\\\\\\\\";
    "\\\\\"";
    "\\\\\'";
    "\\\\\\?";
    unescape_octal_pattern;
    unescape_hex_pattern;
    unescape_utf8_pattern;
  ]

let unescape_octal_char s =
  let s = String.sub s 1 3 in
  Printf.sprintf "%c" (Char.chr (int_of_string ("0o" ^ s)))

let unescape_hex_char s =
  let s = String.sub s 2 2 in
  Printf.sprintf "%c" (Char.chr (int_of_string ("0x" ^ s)))

let unescape_utf8_char s =
  let b = Buffer.create 1 in
  let s = String.sub s 2 4 in
  let c = try Uchar.of_int (int_of_string ("0x" ^ s)) with _ -> Uchar.rep in
  Buffer.add_utf_8_uchar b c;
  Buffer.contents b

let unescape_char = function
  | "\\a" -> "\x07"
  | "\\b" -> "\b"
  | "\\e" -> "\x1b"
  | "\\f" -> "\x0c"
  | "\\n" -> "\n"
  | "\\r" -> "\r"
  | "\\t" -> "\t"
  | "\\v" -> "\x0b"
  | "\\/" -> "/"
  | "\\\\" -> "\\"
  | "\\\"" -> "\""
  | "\\'" -> "'"
  | "\\?" -> "\x3f"
  | s when String.length s = 6 -> unescape_utf8_char s
  | s when String.length s = 4 && s.[1] = 'x' -> unescape_hex_char s
  | s when String.length s = 4 -> unescape_octal_char s
  | _ -> assert false

let unescape_string =
  let rex = Pcre.regexp_or unescape_patterns in
  Pcre.substitute ~rex ~subst:unescape_char

(** Remove line breaks from markdown text. This is useful for reflowing markdown such as when printing doc. *)
let unbreak_md md =
  let must_break = function
    | "" :: _ -> true
    | "```" :: _ -> true
    | line :: _ when line.[0] = '-' (* itemize *) -> true
    | _ -> false
  in
  let rec text = function
    | [] -> ""
    | [line] -> line
    | "```" :: lines -> "```\n" ^ verb lines
    | line :: lines when line = "" || must_break lines ->
        line ^ "\n" ^ text lines
    | line :: lines -> line ^ " " ^ text lines
  and verb = function
    | "```" :: lines -> "```\n" ^ text lines
    | line :: lines -> line ^ "\n" ^ verb lines
    | [] -> "```"
  in
  text (String.split_on_char '\n' md)

(* Here we take care not to introduce new redexes when substituting *)

(* Interpolation:
 * takes a (string -> string) lookup function (raise Not_found on failure) and
 * a string containing special patterns like $(v) or $(if $(v),"bla","bli")
 * and interpolates them just like make does, using the hash table for
 * variable definitions. *)
let interpolate =
  (* TODO Use PCRE *)
  let quoted = "\"\\(\\([^\"\\]\\|\\(\\\\\"\\)\\)*\\)\"" in
  (* 3 groups *)
  let var = "\\$(\\([^()$]+\\))" in
  let re_if =
    (* Groups              1           2 (3 4)   5       6 (7 8)      *)
    (* TODO: use unescape above? *)
    Str.regexp
      ("\\$(if +" ^ var ^ " *, *" ^ quoted ^ "\\( *, *" ^ quoted ^ "\\)?)")
  in
  let unescape = Str.global_replace (Str.regexp "\\\\\\(.\\)") "\\1" in
  fun find s ->
    let find v = try find v with Not_found -> "" in
    let process_if s =
      let s = ref s in
      let changed = ref true in
      while !changed do
        changed := false;
        s :=
          Str.substitute_first re_if
            (fun s ->
              changed := true;
              let v = find (Str.matched_group 1 s) in
              let then_ = Str.matched_group 2 s in
              let else_ = try Str.matched_group 6 s with _ -> "" in
              unescape (if v = "" then else_ else then_))
            !s
      done;
      !s
    in
    let interpolate =
      Str.global_substitute
        (Str.regexp ("\\(.\\|^\\)\\(" ^ var ^ "\\)"))
        (fun s ->
          let p = Str.matched_group 1 s in
          if p = "\\" then Str.matched_group 2 s
          else p ^ find (Str.matched_group 3 s))
    in
    interpolate (process_if s)

(** [which s] is equivalent to /usr/bin/which s, raises Not_found on error *)
let which ~path s =
  let test fname =
    try
      Unix.access fname [Unix.X_OK];
      true
    with _ -> false
  in
  if s = "" then raise Not_found;
  if test s then s
  else List.find test (List.map (fun d -> Filename.concat d s) path)

let which_opt ~path s = try Some (which ~path s) with Not_found -> None

(** Get current timezone. *)
external timezone : unit -> int = "liquidsoap_get_timezone"
  [@@noalloc]

external timezone_by_name : unit -> string * string
  = "liquidsoap_get_timezone_by_name"

(* Same as [Unix.mktime] but honnors [isdst] *)
type tm = {
  tm_sec : int;
  tm_min : int;
  tm_hour : int;
  tm_mday : int;
  tm_mon : int;
  tm_year : int;
  tm_isdst : bool option;
}

external mktime : tm -> float = "liquidsoap_mktime"

let string_of_timezone tz =
  (* TODO: not sure about why we need this... *)
  let tz = -tz in
  Printf.sprintf "%+03d%02d" (tz / 3600) (abs (tz / 60) mod 60)

(** Very partial strftime clone *)
let strftime str : string =
  let t = Unix.localtime (Unix.gettimeofday ()) in
  let assoc =
    [
      ("S", Printf.sprintf "%02d" t.Unix.tm_sec);
      ("M", Printf.sprintf "%02d" t.Unix.tm_min);
      ("H", Printf.sprintf "%02d" t.Unix.tm_hour);
      ("d", Printf.sprintf "%02d" t.Unix.tm_mday);
      ("m", Printf.sprintf "%02d" (t.Unix.tm_mon + 1));
      ("Y", string_of_int (t.Unix.tm_year + 1900));
      ("w", string_of_int t.Unix.tm_wday);
      ("z", string_of_timezone (timezone ()));
      ("%", "%");
    ]
  in
  let subst sub =
    let key = Pcre.get_substring sub 1 in
    try List.assoc key assoc with _ -> "%" ^ key
  in
  Pcre.substitute_substrings ~pat:"%(.)" ~subst str

(** Check if a directory exists. *)
let is_dir d =
  try
    ignore (Sys.readdir d);
    true
  with _ -> false

let dir_exists d = Sys.file_exists d && is_dir d

(** Create a directory, and its parents if needed.
  * Raise Unix_error on error. *)
let rec mkdir ~perm dir =
  if Sys.file_exists dir then
    if is_dir dir then ()
    else raise (Unix.Unix_error (Unix.ENOTDIR, "Utils.mkdir", dir))
  else (
    let up = Filename.dirname dir in
    if up = "." then () else mkdir ~perm up;
    Unix.mkdir dir perm)

(** Expand ~ notation in filenames. *)
let home_unrelate =
  let home = getenv_opt "HOME" in
  let unrel s =
    let len = String.length s in
    if len < 2 then (match home with Some h when s = "~" -> h | _ -> s)
    else (
      match (home, s.[0] = '~', s.[1] = '/') with
        | Some home, true, true ->
            (* Something like ~/data/file *)
            Filename.concat home (String.sub s 2 (len - 2))
        | _, true, false -> (
            (* Something like ~bob/data/file *)
            let index = try String.index s '/' with Not_found -> len in
            let user = String.sub s 1 (index - 1) in
            try
              let home = (Unix.getpwnam user).Unix.pw_dir in
              Filename.concat home (String.sub s index (len - index))
            with Not_found -> s)
        | _ -> s)
  in
  unrel

let get_tempdir () =
  if Sys.win32 then getenv ~default:"C:\\temp" "TEMP"
  else getenv ~default:"/tmp" "TMPDIR"

(** Decode Base64-encoded data *)
let decode64 s =
  let padding = ref 0 in
  let to_int c =
    match c with
      | 'A' .. 'Z' -> int_of_char c - int_of_char 'A'
      | 'a' .. 'z' -> int_of_char c - int_of_char 'a' + 26
      | '0' .. '9' -> int_of_char c - int_of_char '0' + 52
      | '+' -> 62
      | '/' -> 63
      | '=' ->
          incr padding;
          0
      | _ -> failwith "decode64: invalid encoding"
  in
  let result = ref [] in
  let add x = result := char_of_int x :: !result in
  for i = 0 to (String.length s / 4) - 1 do
    (* Read 4 64-digits, i.e. 3 bytes. *)
    let c n = to_int s.[(i * 4) + n] in
    let i = c 3 + (c 2 lsl 6) + (c 1 lsl 12) + (c 0 lsl 18) in
    add ((i land 0xff0000) lsr 16);
    add ((i land 0x00ff00) lsr 8);
    add (i land 0x0000ff)
  done;
  let result =
    (* Remove up to two bytes depending on the padding. *)
    match !padding with
      | 0 -> !result
      | 1 -> List.tl !result
      | 2 -> List.tl (List.tl !result)
      | _ -> failwith "decode64: invalid encoding"
  in
  let len = List.length result in
  let s = Bytes.make len ' ' in
  ignore
    (List.fold_left
       (fun i c ->
         Bytes.set s i c;
         i - 1)
       (len - 1) result);
  Bytes.unsafe_to_string s

(** Base 64 encoding. *)
let encode64 s =
  let digit =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  in
  let extra = String.length s mod 3 in
  let s = match extra with 1 -> s ^ "\000\000" | 2 -> s ^ "\000" | _ -> s in
  let n = String.length s in
  let dst = Bytes.create (4 * (n / 3)) in
  for i = 0 to (n / 3) - 1 do
    let ( := ) j v = Bytes.set dst ((i * 4) + j) digit.[v] in
    let c j = int_of_char s.[(i * 3) + j] in
    let c0 = c 0 and c1 = c 1 and c2 = c 2 in
    0 := c0 lsr 2;
    1 := (c0 lsl 4) land 63 lor (c1 lsr 4);
    2 := (c1 lsl 2) land 63 lor (c2 lsr 6);
    3 := c2 land 63
  done;
  if extra = 1 then (
    Bytes.set dst ((4 * (n / 3)) - 2) '=';
    Bytes.set dst ((4 * (n / 3)) - 1) '=')
  else if extra = 2 then Bytes.set dst ((4 * (n / 3)) - 1) '=';
  Bytes.unsafe_to_string dst

(* This is not guaranteed to work 100% but should
 * be ok on reasonable cases. A problematic cases
 * is for instance: http://bla.com/foo.mp3?gni=bla.truc *)

(** Get a file/uri extension. *)
let get_ext s =
  try
    let rex = Pcre.regexp "\\.([a-zA-Z0-9]+)[^.]*$" in
    let ret = Pcre.exec ~rex s in
    String.lowercase_ascii (Pcre.get_substring ret 1)
  with _ -> raise Not_found

let get_ext_opt s = try Some (get_ext s) with Not_found -> None

let name_of_sockaddr ?(rev_dns = false) ?(show_port = false) a =
  match a with
    | Unix.ADDR_UNIX s -> Printf.sprintf "unix socket %S" s
    | Unix.ADDR_INET (x, p) ->
        let host =
          try
            if not rev_dns then raise Not_found;
            (Unix.gethostbyaddr x).Unix.h_name
          with Not_found -> Unix.string_of_inet_addr x
        in
        if show_port then Printf.sprintf "%s:%i" host p else host

(** Uptime since the application was started. *)
let uptime =
  let base = Unix.gettimeofday () in
  fun () -> Unix.gettimeofday () -. base

(** Generate a string which can be used as a parameter name. *)
let normalize_parameter_string s =
  let s =
    Pcre.substitute ~pat:"( *\\([^\\)]*\\)| *\\[[^\\]]*\\])"
      ~subst:(fun _ -> "")
      s
  in
  let s = Pcre.substitute ~pat:"(\\.+|\\++)" ~subst:(fun _ -> "") s in
  let s = Pcre.substitute ~pat:" +$" ~subst:(fun _ -> "") s in
  let s = Pcre.substitute ~pat:"( +|/+|-+)" ~subst:(fun _ -> "_") s in
  let s = Pcre.substitute ~pat:"\"" ~subst:(fun _ -> "") s in
  let s = String.lowercase_ascii s in
  (* Identifiers cannot begin with a digit. *)
  let s = if Pcre.pmatch ~pat:"^[0-9]" s then "_" ^ s else s in
  s

(** A function to reopen a file descriptor
  * Thanks to Xavier Leroy!
  * Ref: http://caml.inria.fr/pub/ml-archives/caml-list/2000/01/
  *      a7e3bbdfaab33603320d75dbdcd40c37.en.html
  *)
let reopen_out outchan filename =
  flush outchan;
  let fd1 = Unix.descr_of_out_channel outchan in
  let fd2 = Unix.openfile filename [Unix.O_WRONLY; Unix.O_CLOEXEC] 0o666 in
  Unix.dup2 ~cloexec:true fd2 fd1;
  Unix.close fd2

(** The same for inchan *)
let reopen_in inchan filename =
  let fd1 = Unix.descr_of_in_channel inchan in
  let fd2 = Unix.openfile filename [Unix.O_RDONLY; Unix.O_CLOEXEC] 0o666 in
  Unix.dup2 ~cloexec:true fd2 fd1;
  Unix.close fd2

(* See: http://www.onicos.com/staff/iz/formats/ieee.c *)
let float_of_extended_float bytes =
  let float_of_unsigned u =
    let ( - ) = Int32.sub in
    let f = Int32.shift_left Int32.one 31 - Int32.one in
    Int32.to_float (u - f - Int32.one) +. 2147483648.
  in
  let expon =
    ((int_of_char bytes.[0] land 0x7F) lsl 8)
    lor (int_of_char bytes.[1] land 0xff)
  in
  let boc c = Int32.of_int (int_of_char c land 0xff) in
  let ( lsl ) = Int32.shift_left in
  let ( lor ) = Int32.logor in
  let hiMant =
    (boc bytes.[2] lsl 24)
    lor (boc bytes.[3] lsl 16)
    lor (boc bytes.[4] lsl 8)
    lor boc bytes.[5]
  in
  let loMant =
    (boc bytes.[6] lsl 24)
    lor (boc bytes.[7] lsl 16)
    lor (boc bytes.[8] lsl 8)
    lor boc bytes.[9]
  in
  if expon = 0 && hiMant = Int32.zero && loMant = Int32.zero then 0.
  else if expon = 0x7fff then nan
  else (
    let expon = expon - 16383 - 31 in
    let f = ldexp (float_of_unsigned hiMant) expon in
    let f = f +. ldexp (float_of_unsigned loMant) (expon - 32) in
    if int_of_char bytes.[0] land 0x80 <> 0 then -1. *. f else f)

(* From OCaml *)
let file_extension_len ~dir_sep name =
  let rec check i0 i =
    if i < 0 || name.[i] = dir_sep then 0
    else if name.[i] = '.' then check i0 (i - 1)
    else String.length name - i0
  in
  let rec search_dot i =
    if i < 0 || name.[i] = dir_sep then 0
    else if name.[i] = '.' then check i (i - 1)
    else search_dot (i - 1)
  in
  search_dot (String.length name - 1)

let file_extension ?(leading_dot = true) ?(dir_sep = Filename.dir_sep) name =
  let dir_sep = dir_sep.[0] in
  let l = file_extension_len ~dir_sep name in
  let s = if l = 0 then "" else String.sub name (String.length name - l) l in
  try
    match (leading_dot, s.[0]) with
      | false, '.' -> String.sub s 1 (String.length s - 1)
      | _ -> s
  with Invalid_argument _ -> s

let environment () =
  let l = Unix.environment () in
  (* Split at first occurrence of '='. Return v,"" if
   * no '=' could be found. *)
  let split s =
    try
      let pos = String.index s '=' in
      (String.sub s 0 pos, String.sub s (pos + 1) (String.length s - pos - 1))
    with _ -> (s, "")
  in
  let l = Array.to_list l in
  List.map split l

(** Size of an OCaml value (including referred elements) in bytes. *)
let reachable_size x = Obj.reachable_words (Obj.repr x) * Sys.word_size

(** String representation of a size (in bytes). *)
let string_of_size n =
  if n < 1 lsl 10 then Printf.sprintf "%d B" n
  else if n < 1 lsl 20 then
    Printf.sprintf "%.02f KiB" (float_of_int n /. float_of_int (1 lsl 10))
  else if n < 1 lsl 30 then
    Printf.sprintf "%.02f MiB" (float_of_int n /. float_of_int (1 lsl 20))
  else Printf.sprintf "%.02f GiB" (float_of_int n /. float_of_int (1 lsl 30))

(* From dbuenzli/cmdliner *)
let find_cmd cmds =
  let test, null =
    match Sys.os_type with
      | "Win32" -> ("where", " NUL")
      | _ -> ("type", "/dev/null")
  in
  let rec cmd = function
    | (c, args) :: l ->
        if Sys.command (Printf.sprintf "%s %s 1>%s 2>%s" test c null null) = 0
        then Some (if args = "" then c else c ^ " " ^ args)
        else cmd l
    | [] -> None
  in
  cmd cmds

let print_strings ?(pager = false) s =
  let pager = if Sys.getenv_opt "PAGER" = Some "none" then false else pager in
  let default s = Strings.iter (output_substring stdout) s in
  let cmd =
    let cmds = [("less", "-F -X"); ("more", "")] in
    let cmds = try (Sys.getenv "PAGER", "") :: cmds with Not_found -> cmds in
    let cmds =
      try (Sys.getenv "MANPAGER", "") :: cmds with Not_found -> cmds
    in
    find_cmd cmds
  in
  match (pager, cmd) with
    | false, _ | _, None -> default s
    | true, Some pager -> (
        let fname, oc = Filename.open_temp_file "liquidsoap" ".txt" in
        try
          Strings.iter (output_substring oc) s;
          flush oc;
          if Sys.command (Printf.sprintf "%s %s" pager fname) <> 0 then
            default s;
          raise Exit
        with _ ->
          close_out oc;
          Unix.unlink fname)

let print_string ?(pager = false) s =
  if not pager then print_string s
  else print_strings ~pager (Strings.of_string s)

let kprint_string ?(pager = false) f =
  if not pager then f (print_string ~pager)
  else (
    let ans = Strings.Mutable.empty () in
    f (Strings.Mutable.add ans);
    print_strings ~pager (Strings.Mutable.to_strings ans))

(** String representation of a matrix of strings. *)
let string_of_matrix a =
  let height = Array.length a in
  let width = Array.fold_left (fun h a -> max h (Array.length a)) 0 a in
  let len = Array.make width 0 in
  for j = 0 to height - 1 do
    for i = 0 to Array.length a.(j) - 1 do
      len.(i) <- max len.(i) (String.length a.(j).(i))
    done
  done;
  let ans = Strings.Mutable.empty () in
  for j = 0 to height - 1 do
    for i = 0 to Array.length a.(j) - 1 do
      let s = a.(j).(i) in
      if i <> 0 then Strings.Mutable.add ans " ";
      Strings.Mutable.add ans s;
      Strings.Mutable.add ans (String.make (len.(i) - String.length s) ' ')
    done;
    Strings.Mutable.add ans "\n"
  done;
  Strings.Mutable.to_string ans

(* Util to log exception and backtrace together
   when log level is set to info and just exception
   as severe otherwise. Backtrace should be captured as early
   as possible. *)
let log_exception ~(log : Log.t) ~bt msg =
  if log#active 4 (* info *) then log#info "%s\n%s" msg bt
  else log#severe "%s" msg

(** Operations on versions of Liquidsoap. *)
module Version = struct
  type t = int list * string

  (* We assume something like, 2.0.0+git@7e211ffd *)
  let of_string s : t =
    let rex = Pcre.regexp "([\\.\\d]+)([^\\.]+)?" in
    let sub = Pcre.exec ~rex s in
    let num = Pcre.get_substring sub 1 in
    let str = try Pcre.get_substring sub 2 with Not_found -> "" in
    let num = String.split_on_char '.' num |> List.map int_of_string in
    (num, str)

  (** Number part. *)
  let num (v : t) = fst v

  (** String part. *)
  let str (v : t) = snd v

  (** Compare two versions. 2.0.0~foo is less than 2.0.0 *)
  let compare v w =
    let compare_suffixes =
      match (str v, str w) with
        | v, w
          when String.length v > 1
               && String.length w > 1
               && v.[0] = '~'
               && w.[0] = '~' ->
            String.compare v w
        | v, w
          when String.length v > 1
               && String.length w > 1
               && v.[0] = '~'
               && w.[0] <> '~' ->
            -1
        | v, w
          when String.length v > 1
               && String.length w > 1
               && v.[0] <> '~'
               && w.[0] = '~' ->
            1
        | v, "" when String.length v > 1 && v.[0] = '~' -> -1
        | "", w when String.length w > 1 && w.[0] = '~' -> 1
        | v, w -> String.compare v w
    in
    let rec aux v w =
      match (v, w) with
        | m :: _, n :: _ when m < n -> -1
        | m :: _, n :: _ when m > n -> 1
        | _ :: v, _ :: w -> aux v w
        | [], [] -> compare_suffixes
        | [], _ -> -1
        | _, [] -> 1
    in
    aux (num v) (num w)
end

let self_sync_type sources =
  lazy
    (fst
       (List.fold_left
          (fun cur s ->
            match (cur, s#self_sync) with
              | (`Static, None), (`Static, v) -> (`Static, Some v)
              | (`Static, Some v), (`Static, v') when v = v' -> (`Static, Some v)
              | _ -> (`Dynamic, None))
          (`Static, None)
          sources))
