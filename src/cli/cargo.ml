let packages =
  [ ("0install-solver", "2.17")
  ; ("afl-persistent", "1.3")
  ; ("alcotest", "1.4.0")
  ; ("astring", "0.8.5")
  ; ("base", "v0.14.0")
  ; ("bechamel", "0.1.0")
  ; ("bos", "0.2.0")
  ; ("cmdliner", "1.0.4")
  ; ("cohttp", "4.0.0")
  ; ("core", "v0.14.1")
  ; ("ctypes", "0.17.1")
  ; ("dune", "2.8.4")
  ; ("either", "1.0.0")
  ; ("fmt", "0.8.9")
  ; ("fpath", "0.7.2")
  ; ("logs", "0.7.0")
  ; ("lru", "0.3.0")
  ; ("lwt", "5.4.0")
  ; ("memtrace", "0.1.2")
  ; ("mirage", "3.10.1")
  ; ("mirage-clock", "3.1.0")
  ; ("mirage-clock-unix", "3.1.0")
  ; ("mirage-crypto", "0.10.1")
  ; ("optint", "0.1.0")
  ; ("ppx_repr", "0.3.0")
  ; ("repr", "0.3.0")
  ; ("stdio", "v0.14.0")
  ; ("uucp", "13.0.0")
  ; ("uutf", "1.0.2")
  ; ("yojson", "1.7.0")
  ; ("zarith", "1.9.1")
  ]
  |> Vector.of_list ~dummy:("", "")

let setup_logs () =
  let reporter = Progress.logs_reporter () in
  Fmt_tty.setup_std_outputs ();
  Logs_threaded.enable ();
  Logs.set_reporter reporter

let bar =
  let open Progress.Line in
  let total = Vector.length packages in
  list
    [ constf "    %a" Fmt.(styled `Cyan string) "Building"
    ; using fst
        (brackets
           (bar
              ~style:(`Custom (Bar_style.v [ "="; ">"; " " ]))
              ~width:(`Fixed 40) total))
    ; ticker_to total
    ; using snd string
    ]

let rec package_worker (active_packages, reporter) =
  match Vector.pop packages with
  | exception Vector.Empty -> ()
  | package, version ->
      active_packages := package :: !active_packages;
      Logs.app (fun f ->
          f "   %a %s %s" Fmt.(styled `Green string) "Compiling" package version);
      Unix.sleepf (Random.float 1.);
      active_packages := List.filter (( <> ) package) !active_packages;
      reporter ();
      package_worker (active_packages, reporter)

let run () =
  setup_logs ();
  Random.self_init ();
  let cpus = 4 in
  let run_duration = Mtime_clock.counter () in
  let active_packages = ref [] in
  Progress.with_reporter ~config:(Progress.Config.v ~persistent:false ()) bar
    (fun reporter ->
      let reporter () =
        let package_list =
          !active_packages |> List.sort String.compare |> String.concat ", "
        in
        reporter (1, package_list)
      in
      let threads =
        List.init cpus (fun _ ->
            Thread.create package_worker (active_packages, reporter))
      in
      List.iter Thread.join threads);
  Logs.app (fun f ->
      f "    %a in %a"
        Fmt.(styled `Green string)
        "Finished" Mtime.Span.pp
        (Mtime_clock.count run_duration))

module Interject = struct
  let bar ~total =
    let open Progress.Line in
    list
      [ spinner ~color:(Progress.Color.ansi `green) ()
      ; bar total
      ; count_to total
      ]

  let run () =
    let total = 100 in
    Progress.with_reporter (bar ~total) (fun f ->
        for i = 1 to total do
          f 1;
          if i mod 10 = 0 then
            Progress.interject_with (fun () ->
                print_endline (":: Finished " ^ string_of_int i));
          Unix.sleepf 0.025
        done)

end

let examples =
  [ ("cargo", "Port of the Cargo install progress bar", run)
  ; ("interject", "Logging while displaying a progress bar", Interject.run)
  ]

let available_examples () =
  Format.eprintf "Available examples: @.";
  ListLabels.iter examples ~f:(fun (name, desc, _) ->
      Format.eprintf "- %-12s %a@." name
        Fmt.(styled `Faint (parens string))
        desc)

let usage () =
  Format.eprintf "@.";
  available_examples ();
  Format.eprintf "\n%a: dune exec %s%s%s.exe -- [--help] <example_name>@."
    Fmt.(styled `Green string)
    "usage" Filename.current_dir_name Filename.dir_sep
    (Filename.chop_extension __FILE__)

let () =
  Random.self_init ();
  Fmt.set_style_renderer Fmt.stderr `Ansi_tty;
  match Sys.argv with
  | [| _ |] | [| _; "-h" | "-help" | "--help" |] -> usage ()
  | [| _; "--list" |] ->
      ListLabels.iter ~f:(fun (name, _, _) -> print_endline name) examples
  | [| _; name |] -> (
      match
        List.find_opt
          (fun (n, _, _) -> n = String.lowercase_ascii name)
          examples
      with
      | None ->
          Format.eprintf "%a: unrecognised example name `%a`.@.@."
            Fmt.(styled `Bold @@ styled `Red string)
            "Error"
            Fmt.(styled `Cyan string)
            name;
          available_examples ();
          exit 1
      | Some (_, _, f) -> f ())
  | _ ->
      usage ();
      exit 1
