open MetadataBase

module R = Reader

(* Tag normalization. *)
let tagn =
  [
    "IART", "artist";
    "ICMT", "comment";
    "ICOP", "copyright";
    "ICRD", "date";
    "ICRD", "date";
    "IGNR", "genre";
    "INAM", "title";
    "IPRD", "album";
    "IPRT", "track";
    "ISFT", "encoder"
  ]

let parse f : metadata =
  if R.read f 4 <> "RIFF" then raise Invalid;
  let _ (* file size *) = R.int32_le f in
  if R.read f 4 <> "AVI " then raise Invalid;
  let ans = ref [] in
  let chunk () =
    let tag = R.read f 4 in
    let size = R.int32_le f in
    if tag <> "LIST" then R.drop f size else
      let subtag = R.read f 4 in
      match subtag with
      | "INFO" ->
        let remaining = ref (size - 4) in
        while !remaining > 0 do
          let tag = R.read f 4 in
          let size = R.int32_le f in
          let s = R.read f (size - 1) in
          R.drop f 1; (* null-terminated *)
          let padding = size mod 2 in
          R.drop f padding;
          remaining := !remaining - (8 + size + padding);
          let tag = match List.assoc_opt tag tagn with Some tag -> tag | None -> tag in
          ans := (tag, s) :: !ans
        done
      | "movi" -> raise Exit (* stop parsing there *)
      | _ -> R.drop f (size - 4)
  in
  try
    while true do
      chunk ()
    done;
    assert false
  with _ -> List.rev !ans
  
let parse_file = R.with_file parse
