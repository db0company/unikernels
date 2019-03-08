(* (c) 2017, 2018 Hannes Mehnert, all rights reserved *)

open Lwt.Infix

open Mirage_types_lwt

module Main (R : RANDOM) (P : PCLOCK) (M : MCLOCK) (T : TIME) (S : STACKV4) = struct
  module D = Dns_mirage_resolver.Make(R)(P)(M)(T)(S)

  let start _r pclock mclock _ s _ =
    let trie =
      List.fold_left
        (fun trie (k, v) -> Dns_trie.insertb k v trie)
        Dns_trie.empty Dns_resolver_root.reserved_zones
    in
    let keys = [
      Domain_name.of_string_exn ~hostname:false "foo._key-management" ,
      { Dns_packet.flags = 0 ; key_algorithm = Dns_enum.SHA256 ; key = Cstruct.of_string "/NzgCgIc4yKa7nZvWmODrHMbU+xpMeGiDLkZJGD/Evo=" }
    ] in
    (match Dns_trie.check trie with
     | Ok () -> ()
     | Error e ->
       Logs.err (fun m -> m "check after update returned %a" Dns_trie.pp_err e)) ;
    let now = M.elapsed_ns mclock in
    let server =
      UDns_server.Primary.create ~keys ~a:[UDns_server.Authentication.tsig_auth]
        ~tsig_verify:Dns_tsig.verify ~tsig_sign:Dns_tsig.sign ~rng:R.generate
        trie
    in
    let p = UDns_resolver.create now R.generate server in
    D.resolver ~timer:1000 ~root:true s p ;
    S.listen s
end
