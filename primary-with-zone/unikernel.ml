(* (c) 2017, 2018 Hannes Mehnert, all rights reserved *)

open Lwt.Infix

open Mirage_types_lwt

module Main (R : RANDOM) (P : PCLOCK) (M : MCLOCK) (T : TIME) (S : STACKV4) (KV : KV_RO) = struct

  module D = Dns_mirage_server.Make(P)(M)(T)(S)

  let start _rng pclock mclock _ s kv _ =
    KV.get kv (Mirage_kv.Key.v "zone") >>= function
    | Error e -> Lwt.fail_with "couldn't get zone file"
    | Ok data -> match Zonefile.load [] data with
      | Error msg ->
        Logs.err (fun m -> m "zonefile.load: %s" msg) ;
        Lwt.fail_with "zone parser"
      | Ok rrs ->
        let trie = Dns_trie.insert_map (Dns_map.of_rrs rrs) Dns_trie.empty in
        match Dns_trie.check trie with
         | Error e ->
           Logs.err (fun m -> m "error %a during check()" Dns_trie.pp_err e) ;
           Lwt.fail_with "check failed"
         | Ok () ->
           let t =
             UDns_server.Primary.create ~a:[UDns_server.Authentication.tsig_auth]
               ~tsig_verify:Dns_tsig.verify ~tsig_sign:Dns_tsig.sign
               ~rng:R.generate trie
           in
           D.primary s t ;
           S.listen s
end
