-module(ar_node).
-export([start/0, start/1, start/2, start/3, start/4, start/5, start/6, start/7]).
-export([stop/1]).
-export([get_blocks/1, get_block/2, get_full_block/2]).
-export([get_tx/2]).
-export([get_peers/1]).
-export([get_wallet_list/1]).
-export([get_hash_list/1]).
-export([get_trusted_peers/1]).
-export([get_balance/2]).
-export([get_last_tx/2, get_last_tx_from_floating/2]).
-export([get_pending_txs/1, get_full_pending_txs/1]).
-export([get_current_diff/1, get_diff/1]).
-export([get_floating_wallet_list/1, generate_floating_wallet_list/2]).
-export([get_waiting_txs/1, get_all_known_txs/1]).
-export([get_current_block/1]).
-export([get_reward_addr/1]).
-export([get_reward_pool/1]).
-export([find_recall_hash/2]).
-export([find_recall_block/1]).
-export([find_sync_block/1]).
-export([mine/1, mine_at_diff/2, automine/1, truncate/1]).
-export([add_block/3, add_block/4, add_block/5]).
-export([add_tx/2]).
-export([add_peers/2]).
-export([calculate_reward/2, calculate_static_reward/1]).
-export([rejoin/2]).
-export([filter_all_out_of_order_txs/2]).
-export([apply_tx/2, apply_txs/2]).
-export([apply_mining_reward/4]).
-export([validate/5, validate/8, validate_wallet_list/1]).
-export([calculate_reward_pool/4, calculate_proportion/3]).
-export([print_reward_addr/0]).
-export([set_reward_addr/2, set_reward_addr_from_file/1, generate_and_set_reward_addr/0]).
-export([retry_block/4, retry_full_block/4]). % DEPRECATED (27/06/2018)
-export([start_link/1]).
-export([set_loss_probability/2, set_delay/2, set_mining_delay/2, set_xfer_speed/2]).

-export([wallet_two_transaction_test_slow/0]).
-export([single_wallet_double_tx_before_mine_test_slow/0]).
-export([single_wallet_double_tx_wrong_order_test_slow/0]).
-export([tx_threading_test_slow/0]).
-export([bogus_tx_thread_test_slow/0]).
-export([wallet_transaction_test_slow/0]).
-export([filter_out_of_order_txs_test_slow/0]).
-export([filter_all_out_of_order_txs_test_slow/0]).
-export([filter_all_out_of_order_txs_large_test_slow/0]).
-export([filter_out_of_order_txs_large_test_slow/0]).
-export([large_weakly_connected_blockweave_with_data_test_slow/0]).
-export([large_blockweave_with_data_test_slow/0]).
-export([medium_blockweave_mine_multiple_data_test_slow/0]).
-include("ar.hrl").
-include_lib("eunit/include/eunit.hrl").

%%% Blockweave maintaining nodes in the Arweave system.

% NB: The potential_txs field stores the set of txs that contradict those
% already stored within the txs field. That is those that have the same last
% tx reference as one already held in txs.
%
% These txs are not dropped as when a block is a mined blockshadows do not
% redistribute the set mined on, only their IDs. As such they may be required
% to validate newly distributed blocks from other nodes in the network.
%
-record(state, {
	hash_list = not_joined, % current full hashlist
	wallet_list = [], % current up to date walletlist
	floating_wallet_list = [], % up to date walletlist with new txs applied
	height = 0, % current height of the blockweave
	gossip, % Gossip protcol state
	txs = [], % set of new txs to be mined into the next block
	miner, % PID of the mining process
	mining_delay = 0, % delay on mining, used for netework simulation
	automine = false, % boolean dictating if a node should automine
	reward_addr = unclaimed, % reward address for mining a new block
	trusted_peers = [], % set of trusted peers used to join on
	waiting_txs = [], % set of txs on timeout whilst network distribution occurs
	potential_txs = [], % set of valid but contradictory txs
    tags = [], % nodes tags to apply to a block when mining
	reward_pool = 0, % current mining rewardpool of the weave
	diff = 0, % current mining difficulty of the weave (no. of preceeding zero)
	last_retarget, % timestamp at which the last difficulty retarget occurred
	weave_size = 0 % current size of the weave in bytes (only inc. data tx size)
}).

%% @doc Maximum number of blocks to hold at any time.
%% NOTE: This value should be greater than ?RETARGET_BLOCKS + 1
%% in order for the TNT test suite to pass.
-define(MAX_BLOCKS, ?RETARGET_BLOCKS).

%% @doc Ensure this number of the last blocks are not dropped.
-define(KEEP_LAST_BLOCKS, 5).

%% @doc The time to poll peers for a new current block.
-define(POLL_TIME, 60*100).

%% @doc Start a node, linking to a supervisor process
start_link(Args) ->
	PID = erlang:apply(ar_node, start, Args),
	{ok, PID}.

%% @doc Start a node server loop with a set of optional parameters.
% Peers: the set of PID/IP that the node communicates with
% Blocks: the initial blocks to spawn with, if none, not_joined atom
% MiningDelay: delay in mining, used primarily for network simulation
% RewardAddr: the address in which mining rewards will be attributed with
% AutoJoin: boolean stating if a node should automatically attempt to join
% Diff: starting diff of the network (?DEFAULT_DIFF)
% LastRetarget: timestamp (seconds) stating when difficulty was last changed
start() ->
    start([]).
start(Peers) ->
    start(
        Peers,
        not_joined
    ).
start(Peers, Bs) ->
    start(
        Peers,
        Bs,
        0
    ).
start(Peers, Bs, MiningDelay) ->
    start(
        Peers,
        Bs,
        MiningDelay,
        unclaimed
    ).
start(Peers, HashList, MiningDelay, RewardAddr) ->
	start(
        Peers,
        HashList,
        MiningDelay,
        RewardAddr,
        true
    ).
start(Peers, Bs = [B | _], MiningDelay, RewardAddr, AutoJoin)
        when is_record(B, block) ->
	lists:map(
        fun ar_storage:write_block/1,
        Bs
    ),
    start(
        Peers,
        [B#block.indep_hash | B#block.hash_list],
        MiningDelay,
        RewardAddr,AutoJoin
    );
start(Peers, HashList, MiningDelay, RewardAddr, AutoJoin) ->
	start(
        Peers,
        HashList,
        MiningDelay,
        RewardAddr,
        AutoJoin,
        ?DEFAULT_DIFF
    ).
start(Peers, HashList, MiningDelay, RewardAddr, AutoJoin, Diff) ->
	start(
        Peers,
        HashList,
        MiningDelay,
        RewardAddr,
        AutoJoin,
        Diff,
        os:system_time(seconds)
    ).
start(Peers, Bs = [B | _], MiningDelay, RewardAddr, AutoJoin, Diff, LastRetarget)
        when is_record(B, block) ->
	lists:map(
        fun ar_storage:write_block/1,
        Bs
    ),
	start(
        Peers,
        [B#block.indep_hash | B#block.hash_list],
        MiningDelay,
        RewardAddr,
        AutoJoin,
        Diff,
        LastRetarget
    );
start(Peers, HashList, MiningDelay, RewardAddr, AutoJoin, Diff, LastRetarget) ->
    % spawns the node server process
	PID = spawn(
		fun() ->
            % join the node to the network
			case {HashList, AutoJoin} of
				{not_joined, true} ->
					ar_join:start(self(), Peers);
				_ ->
					do_nothing
			end,
			Gossip =
				ar_gossip:init(
					lists:filter(
						fun is_pid/1,
						Peers
					)
				),
			Hashes = ar_util:wallets_from_hashes(HashList),
			Height = ar_util:height_from_hashes(HashList),
			RewardPool =
				case HashList of
					not_joined -> 0;
					[H | _] -> (ar_storage:read_block(H))#block.reward_pool
				end,
			WeaveSize =
					case HashList of
						not_joined -> 0;
						[H2 | _] -> (ar_storage:read_block(H2))#block.weave_size
					end,
			server(
				#state {
					gossip = Gossip,
					hash_list = HashList,
					wallet_list = Hashes,
					floating_wallet_list = Hashes,
					mining_delay = MiningDelay,
					reward_addr = RewardAddr,
					reward_pool = RewardPool,
					height = Height,
					trusted_peers = Peers,
					diff = Diff,
					last_retarget = LastRetarget,
					weave_size = WeaveSize
				}
			)
		end
    ),
	ar_http_iface:reregister(http_entrypoint_node, PID),
	PID.

%% @doc Stop a node server loop and its subprocesses.
stop(Node) ->
	Node ! stop,
	ok.

%% @doc Get the current top block.
%% If found the result will be a block with tx references, not a full block.
% TODO: standardize return, unavailable | not_found.
get_current_block(Peers) when is_list(Peers) ->
    % ask list of external peers for block
	lists:foldl(
		fun(Peer, Acc) ->
			case is_atom(Acc) of
				false -> Acc;
				true ->
					B = get_current_block(Peer),
					case is_atom(B) of
						true -> Acc;
						false -> B
					end
			end
		end,
		unavailable,
		Peers
	);
get_current_block(Peer) when is_pid(Peer) ->
    % ask own node server for block
	Peer ! {get_current_block, self()},
	receive
		{block, CurrentBlock} -> CurrentBlock
	after ?LOCAL_NET_TIMEOUT ->
		not_found
	end;
get_current_block(Peer) ->
    % handle external peer request
	ar_http_iface:get_current_block(Peer).

%% @doc Return the entire hashlist from a node.
% TODO: Change references to hashlist, not blocklist.
% Code duplication against get_hashlist function.
get_blocks(Node) ->
	Node ! {get_blocks, self()},
	receive
		{blocks, Node, Bs} -> Bs
	after ?LOCAL_NET_TIMEOUT ->
		not_found
	end.

%% @doc Get a specific block via blocks indep_hash.
%% If found the result will be a block with tx references, not a full block.
get_block(Peers, ID) when is_list(Peers) ->
    % ask list of external peers for block
	% ar:d([{getting_block, ar_util:encode(ID)}, {peers, Peers}]),
	case ar_storage:read_block(ID) of
		unavailable ->
			lists:foldl(
				fun(Peer, Acc) ->
					case is_atom(Acc) of
						false -> Acc;
						true ->
							B = get_block(Peer, ID),
							case is_atom(B) of
								true -> Acc;
								false -> B
							end
					end
				end,
				unavailable,
				Peers
			);
		Block -> Block
	end;
get_block(Proc, ID) when is_pid(Proc) ->
    % attempt to get block from nodes local storage
	ar_storage:read_block(ID);
get_block(Host, ID) ->
    % handle external peer request
	ar_http_iface:get_block(Host, ID).

%% @doc Get a specific full block (a block containing full txs) via
%% blocks indep_hash.
get_full_block(Peers, ID) when is_list(Peers) ->
    % check locally first, if not found ask list of external peers for block
	case ar_storage:read_block(ID) of
		unavailable ->
			lists:foldl(
				fun(Peer, Acc) ->
					case is_atom(Acc) of
						false -> Acc;
						true ->
							Full = try get_full_block(Peer, ID) catch _:_ -> unavailable end,
							case is_atom(Full) of
								true -> Acc;
								false -> Full
							end
					end
				end,
				unavailable,
				Peers
			);
		B ->
			case make_full_block(ID) of
				unavailable ->
					ar_storage:invalidate_block(B),
					get_full_block(Peers, ID);
				FinalB -> FinalB
			end
	end;
get_full_block(Proc, ID) when is_pid(Proc) ->
    % attempt to get block from local storage and add transactions
	make_full_block(ID);
get_full_block(Host, ID) ->
    % handle external peer request
	ar_http_iface:get_full_block(Host, ID).

%% @doc Get a specific encrypted block via the blocks indep_hash.
%% If the block is found locally an unencrypted block will be returned.
get_encrypted_block(Peers, ID) when is_list(Peers) ->
    % check locally first, if not found ask list of external peers for
    % encrypted block
	case ar_storage:read_block(ID) of
		unavailable ->
			lists:foldl(
				fun(Peer, Acc) ->
					case is_atom(Acc) of
						false -> Acc;
						true ->
							B = get_encrypted_block(Peer, ID),
							case is_atom(B) of
								true -> Acc;
								false -> B
							end
					end
				end,
				unavailable,
				Peers
			);
		Block -> Block
	end;
get_encrypted_block(Proc, ID) when is_pid(Proc) ->
    % attempt to get block from local storage
    % NB: if found block returned will not be encrypted
	ar_storage:read_block(ID);
get_encrypted_block(Host, ID) ->
    % handle external peer request
	ar_http_iface:get_encrypted_block(Host, ID).

%% @doc Get a specific encrypted full block (a block containing full txs) via
%% the blocks indep_hash.
%% If the block is found locally an unencrypted block will be returned.
get_encrypted_full_block(Peers, ID) when is_list(Peers) ->
    % check locally first, if not found ask list of external peers for
    % encrypted block
	case ar_storage:read_block(ID) of
		unavailable ->
			lists:foldl(
				fun(Peer, Acc) ->
					case is_atom(Acc) of
						false -> Acc;
						true ->
							Full = get_encrypted_full_block(Peer, ID),
							case is_atom(Full) of
								true -> Acc;
								false -> Full
							end
					end
				end,
				unavailable,
				Peers
			);
		_Block -> make_full_block(ID)
	end;
get_encrypted_full_block(Proc, ID) when is_pid(Proc) ->
    % attempt to get block from local storage and make full
    % NB: if found block returned will not be encrypted
	make_full_block(ID);
get_encrypted_full_block(Host, ID) ->
    % handle external peer request
    ar_http_iface:get_encrypted_full_block(Host, ID).

%% @doc Convert a block with tx references into a full block, that is a block
%% containing the entirety of all its referenced txs.
make_full_block(ID) ->
	case ar_storage:read_block(ID) of
		unavailable -> unavailable;
		BlockHeader ->
			FullB =
				BlockHeader#block{
					txs =
						ar_node:get_tx(
							whereis(http_entrypoint_node),
							BlockHeader#block.txs
						)
				},
			case [ NotTX || NotTX <- FullB#block.txs, is_atom(NotTX) ] of
				[] -> FullB;
				_ -> unavailable
			end
    end.

% DEPRECATED (27/06/2018)
%% @doc Reattempts to find a block from a node retrying up to Count times.
retry_block(_, _, Response, 0) ->
	Response;
retry_block(Host, ID, _, Count) ->
	case get_block(Host, ID) of
		not_found ->
			timer:sleep(3000),
			retry_block(Host, ID, not_found, Count-1);
		unavailable ->
			timer:sleep(3000),
			retry_block(Host, ID, unavailable, Count-1);
		B -> B
    end.

% DEPRECATED (27/06/2018)
%% @doc Reattempts to find a full block from a node retrying up to Count times.
retry_full_block(_, _, Response, 0) ->
	Response;
retry_full_block(Host, ID, _, Count) ->
	case get_full_block(Host, ID) of
		not_found ->
			timer:sleep(3000),
			retry_full_block(Host, ID, not_found, Count-1);
		unavailable ->
			timer:sleep(3000),
			retry_full_block(Host, ID, unavailable, Count-1);
		B -> B
	end.

% DEPRECATED (27/06/2018)
%% @doc Reattempts to find an encrypted full block from a node retrying
%% up to Count times.
retry_encrypted_full_block(_, _, Response, 0) ->
	Response;
retry_encrypted_full_block(Host, ID, _, Count) ->
	case get_encrypted_full_block(Host, ID) of
		not_found ->
			timer:sleep(3000),
			retry_encrypted_full_block(Host, ID, not_found, Count-1);
		unavailable ->
			timer:sleep(3000),
			retry_encrypted_full_block(Host, ID, unavailable, Count-1);
		B -> B
	end.

%% @doc Return a specific tx from a node, if it has it.
%% TODO: Should catch case return empty list or not_found atom.
get_tx(_, []) -> [];
get_tx(Peers, ID) when is_list(Peers) ->
    % check locally first, if not found in storage nor nodes state ask
    % list of external peers for tx
	ar:d([{getting_tx, ID}, {peers, Peers}]),
	case
		{
			ar_storage:read_tx(ID),
			lists:keyfind(ID, 2, get_full_pending_txs(whereis(http_entrypoint_node)))
		} of
		{unavailable, false} ->
			lists:foldl(
				fun(Peer, Acc) ->
					case is_atom(Acc) of
						false -> Acc;
						true ->
							T = get_tx(Peer, ID),
							case is_atom(T) of
								true -> Acc;
								false -> T
							end
					end
				end,
				unavailable,
				Peers
			);
		{TX, false} -> TX;
		{unavailable, TX} -> TX;
		{TX, _} -> TX
	end;
get_tx(Proc, ID) when is_pid(Proc) ->
    % attempt to get tx from local storage
	%ar:d({pending, get_full_pending_txs(whereis(http_entrypoint_node))}),
	ar_storage:read_tx(ID);
get_tx(Host, ID) ->
    % handle external peer request
	ar_http_iface:get_tx(Host, ID).

%% @doc Gets the set of all known txs from the node.
%% This set includes those on timeout waiting to distribute around the
%% network, the potentially valid txs as well as those being mined on.
get_all_known_txs(Node) ->
	Node ! {get_all_known_txs, self()},
	receive
		{all_known_txs, TXs} -> TXs
	    after ?LOCAL_NET_TIMEOUT -> []
	end.

%% @doc Get the set of trusted peers.
%% The set of trusted peers is that in whcih where joined on.
get_trusted_peers(Proc) when is_pid(Proc) ->
	Proc ! {get_trusted_peers, self()},
	receive
		{peers, Ps} -> Ps
	    after ?LOCAL_NET_TIMEOUT -> []
	end;
get_trusted_peers(_) ->
	unavailable.

%% @doc Sends a message to the node server instructing a rejoin on the list
%% of trusted peers. Trusted peers are those that were initially joined on.
rejoin(Proc, Peers) ->
	Proc ! {rejoin, Peers}.

%% @doc Get the list of peers from the nodes gossip state.
%% This is the list of peers that node will request blocks/txs from and will
%% distribute its mined blocks to.
get_peers(Proc) when is_pid(Proc) ->
	Proc ! {get_peers, self()},
	receive
		{peers, Ps} -> Ps
	    after ?LOCAL_NET_TIMEOUT -> []
	end;
get_peers(Host) ->
	ar_http_iface:get_peers(Host).

%% @doc Get the current wallet list from the node.
%% This wallet list is up to date to the latest block held.
get_wallet_list(Node) ->
    Node ! {get_walletlist, self()},
    receive
		{walletlist, WalletList} -> WalletList
	    after ?LOCAL_NET_TIMEOUT -> []
	end.

%% @doc Get the current waiting tx list from a node.
get_waiting_txs(Node) ->
	Node ! {get_waiting_txs, self()},
	receive
		{waiting_txs, Waiting} -> Waiting
		after ?LOCAL_NET_TIMEOUT -> error(could_not_get_waiting_txs)
	end.

%% @doc Get the current hash list held by the node.
%% This hash list is up to date to the latest block held.
get_hash_list(Node) ->
    Node ! {get_hashlist, self()},
    receive
		{hashlist, not_joined} -> [];
		{hashlist, HashList} -> HashList
	    after ?LOCAL_NET_TIMEOUT -> []
	end.

%% @doc Get the current balance of a given wallet address.
%% The balance returned is in relation to the nodes current wallet list.
get_balance(Node, Addr) when ?IS_ADDR(Addr) ->
	Node ! {get_balance, self(), Addr},
	receive
		{balance, Addr, B} -> B
	    after ?LOCAL_NET_TIMEOUT -> node_unavailable
	end;
get_balance(Node, WalletID) ->
	get_balance(Node, ar_wallet:to_address(WalletID)).

%% @doc Get the last tx id associated with a given wallet address.
%% Should the wallet not have made a tx the empty binary will be returned.
% TODO: Timeout returns an empty binary, this is also a valid return.
get_last_tx(Node, Addr) when ?IS_ADDR(Addr) ->
	Node ! {get_last_tx, self(), Addr},
	receive
		{last_tx, Addr, LastTX} -> LastTX
	    after ?LOCAL_NET_TIMEOUT -> <<>>
	end;
get_last_tx(Node, WalletID) ->
	get_last_tx(Node, ar_wallet:to_address(WalletID)).

%% @doc Get the last tx id associated with a a given wallet address from the
%% floating wallet list.
%% Should the wallet not have made a tx the empty binary will be returned.
% TODO: Duplicate of get_last_tx, returns empty binary on timeout, this is also
% a valid return.
get_last_tx_from_floating(Node, Addr) when ?IS_ADDR(Addr) ->
	Node ! {get_last_tx_from_floating, self(), Addr},
	receive
		{last_tx_from_floating, Addr, LastTX} -> LastTX
	    after ?LOCAL_NET_TIMEOUT -> <<>>
	end;
get_last_tx_from_floating(Node, WalletID) ->
	get_last_tx_from_floating(Node, ar_wallet:to_address(WalletID)).

%% @doc Returns a list of pending transactions.
%% Pending transactions are those that are valid, but not currently actively
%% being mined as they are waiting to be distributed around the network.
get_pending_txs(Node) ->
	Node ! {get_txs, self()},
	receive
		{all_txs, Txs} -> [T#tx.id || T <- Txs]
	    after ?LOCAL_NET_TIMEOUT -> []
	end.
get_full_pending_txs(Node) ->
	Node ! {get_txs, self()},
	receive
		{all_txs, Txs} -> Txs
	    after ?LOCAL_NET_TIMEOUT -> []
	end.

%% @doc Returns the floating wallet list held by the node.
%% The floating wallet list is the current wallet list with the txs being
%% mined on applied to it.
get_floating_wallet_list(Node) ->
    Node ! {get_floatingwalletlist, self()},
    receive
		{floatingwalletlist, WalletList} -> WalletList
	    after ?LOCAL_NET_TIMEOUT -> []
	end.

%% @doc Returns the new difficulty of next mined block.
% TODO: Function name is confusing, returns the new difficulty being mined on,
% not the 'current' diff (that of the latest block)
get_current_diff(Node) ->
    Node ! {get_current_diff, self()},
    receive
		{current_diff, Diff} -> Diff
	    after ?LOCAL_NET_TIMEOUT -> 1
	end.

%% @doc Returns the difficulty of the last successfully mined block.
%% Returns the difficulty of the current block (not of that being mined).
get_diff(Node) ->
	Node ! {get_diff, self()},
	receive
		{diff, Diff} -> Diff
	    after ?LOCAL_NET_TIMEOUT -> 1
	end.

%% @doc Get the current rewardpool from the node.
get_reward_pool(Node) ->
	Node ! {get_reward_pool, self()},
	receive
		{reward_pool, RewardPool} -> RewardPool
	    after ?LOCAL_NET_TIMEOUT -> 0
	end.

%% @doc Get the reward address attributed to the node.
%% This is the wallet address that should the node successfully mine a block
%% the reward will be credited to.
get_reward_addr(Node) ->
	Node ! {get_reward_addr, self()},
	receive
		{reward_addr, Addr} -> Addr
	after ?LOCAL_NET_TIMEOUT -> 0
	end.

%% @doc Set the reward address of the node.
%% This is the address mining rewards will be credited to.
set_reward_addr(Node, Addr) ->
	Node ! {set_reward_addr, Addr}.

%% @doc Set the reward address of the node from an Arweave keyfile.
%% This is the address mining rewards will be credited to.
set_reward_addr_from_file(Filepath) ->
	{_Priv, Pub} = ar_wallet:load(Filepath),
	set_reward_addr(whereis(http_entrypoint_node), ar_wallet:to_address(Pub)),
	ar:report(
		[
			{new_reward_address, ar_wallet:to_address(Pub)}
		]
	).

%% @doc Generate a new keyfile and set the reward address of the node to the
%% wallets address.
%% This is the address mining rewards wiwll be credited to.
generate_and_set_reward_addr() ->
	{_Priv, Pub} = ar_wallet:new(),
	set_reward_addr(whereis(http_entrypoint_node), ar_wallet:to_address(Pub)),
	ar:report(
		[
			{new_reward_address, ar_wallet:to_address(Pub)}
		]
	).

%% @doc Pretty print the reward address of the node.
print_reward_addr() ->
	ar_util:encode(get_reward_addr(whereis(http_entrypoint_node))).

%% @doc Trigger a node to start mining a block.
mine(Node) ->
	Node ! mine.

%% @doc Trigger a node to start mining a block at a certain difficulty.
mine_at_diff(Node, Diff) ->
	Node ! {mine_at_diff, Diff}.

%% @doc Trigger a node to mine continually.
automine(Node) ->
	Node ! automine.

%% @doc Cause a node to forget all but the latest block.
%% Used primarily for testing, simulating newly joined node.
truncate(Node) ->
	Node ! truncate.

%% @doc Set the likelihood that a message will be dropped in transmission.
%% Used primarily for testing, simulating packet loss.
set_loss_probability(Node, Prob) ->
	Node ! {set_loss_probability, Prob}.

%% @doc Set the max network latency delay for a node.
%% Used primarily for testing, simulating transmission delays.
set_delay(Node, MaxDelay) ->
	Node ! {set_delay, MaxDelay}.

%% @doc Set the number of milliseconds to wait between hashes.
%% Used primarily for testing, simulating lower hasing power machine.
set_mining_delay(Node, Delay) ->
	Node ! {set_mining_delay, Delay}.

%% @doc Set the number of bytes the node can transfer in a second.
%% Used primarily for testing, simulating node connection strengths.
set_xfer_speed(Node, Speed) ->
	Node ! {set_xfer_speed, Speed}.

%% @doc Add a transaction to the node server loop.
%% If accepted the tx will enter the waiting pool before being mined into the
%% the next block.
%% If the tx contradicts another in the tx mining pool it will be moved to
%% the list of potential txs for potential foreign block verification.
add_tx(GS, TX) when is_record(GS, gs_state) ->
	{NewGS, _} = ar_gossip:send(GS, {add_tx, TX}),
	NewGS;
add_tx(Node, TX) when is_pid(Node) ->
	Node ! {add_tx, TX},
	ok;
add_tx(Host, TX) ->
	ar_http_iface:send_new_tx(Host, TX).

%% @doc Add a new block to the node server loop.
%% If accepted the nodes state will change.
add_block(Conn, NewB, RecallB) ->
	add_block(
        Conn,
        NewB,
        RecallB,
        NewB#block.height
    ).
add_block(Conn, NewB, RecallB, Height) ->
	add_block(
        Conn,
        undefined,
        NewB,
        RecallB,
        Height
    ).
add_block(GS, Peer, NewB, RecallB, Height) when is_record(GS, gs_state) ->
    {NewGS, _} =
        ar_gossip:send(
            GS, {new_block, Peer, Height, NewB, RecallB}
        ),
	NewGS;
add_block(Node, Peer, NewB, RecallB, Height) when is_pid(Node) ->
	Node ! {new_block, Peer, Height, NewB, RecallB},
	ok;
add_block(Host, Peer, NewB, RecallB, _Height) ->
	ar_http_iface:send_new_block(Host, Peer, NewB, RecallB),
	ok.

%% @doc Request to add a list of peers to the node server loop.
add_peers(Node, Peer) when not is_list(Peer) ->
    add_peers(Node, [Peer]);
add_peers(Node, Peers) ->
	%ar:d([{node, self()}, {requesting_add_peers, Peers}]),
	Node ! {add_peers, Peers},
	ok.

%% @doc The main node server loop.
server(
	S = #state {
		gossip = GS,
		hash_list = HashList,
		wallet_list = WalletList,
		floating_wallet_list = FloatingWalletList
	}) ->
	try (
        receive
            Msg when is_record(Msg, gs_msg) ->
                % We have received a gossip mesage. Use the library to process it.
                case ar_gossip:recv(GS, Msg) of
                    {NewGS, {new_block, Peer, _Height, NewB, RecallB}} ->
                        %ar:d([{block, NewB}, {hash_list, HashList}]),
                        process_new_block(
                            S,
                            NewGS,
                            NewB,
                            RecallB,
                            Peer,
                            HashList
                        );
                    {NewGS, {add_tx, TX}} ->
                        ConflictingTXs =
                            [
                                T
                            ||
                                T <-
                                    (
                                        S#state.txs ++
                                        S#state.waiting_txs ++
                                        S#state.potential_txs
                                    ),
                                (
                                    (T#tx.last_tx == TX#tx.last_tx) and
                                    (T#tx.owner == TX#tx.owner)
                                )
                            ],
                        case ConflictingTXs of
                            [] ->
                                timer:send_after(
                                    calculate_delay(byte_size(TX#tx.data)),
                                    {apply_tx, TX}
                                ),
                                server(
                                    S#state {
                                        waiting_txs =
                                            ar_util:unique(
                                                [TX | S#state.waiting_txs]
                                            ),
                                        gossip = NewGS
                                    }
                                );
                            _ ->
                                server(
                                    S#state {
                                        potential_txs =
                                            ar_util:unique(
                                                [TX | S#state.potential_txs]
                                            ),
                                        gossip = NewGS
                                    }
                                    )
                        end;
                    {NewGS, ignore} ->
                        server(S#state { gossip = NewGS });
                    {NewGS, X} ->
                        ar:report(
                            [
                                {node, self()},
                                {unhandeled_gossip_msg, X}
                            ]
                        ),
                        server(S#state { gossip = NewGS })
                end;
            {add_tx, TX} ->
                ConflictingTXs =
                    [
                        T
                    ||
                        T <-
                            (
                                S#state.txs ++
                                S#state.waiting_txs ++
                                S#state.potential_txs
                            ),
                        (
                            (T#tx.last_tx == TX#tx.last_tx) and
                            (T#tx.owner == TX#tx.owner)
                        )
                    ],
                case ConflictingTXs of
                    [] ->
                        timer:send_after(
                            calculate_delay(byte_size(TX#tx.data)),
                            {apply_tx, TX}
                        ),
                        server(
                            S#state {
                                waiting_txs =
                                    ar_util:unique(
                                        [TX | S#state.waiting_txs]
                                    )
                            }
                        );
                    _ ->
                        ar_tx_db:put(TX#tx.id, ["last_tx_not_valid "]),
                        server(
                            S#state {
                                potential_txs =
                                    ar_util:unique(
                                        [TX | S#state.potential_txs]
                                    )
                            }
                        )
                end;
            {apply_tx, TX} ->
                {NewGS, _} = ar_gossip:send(GS, {add_tx, TX}),
                add_tx_to_server(S, NewGS, TX);
            {new_block, Peer, Height, NewB, RecallB} ->
                % We have a new block. Distribute it to the
                % gossip network.
                {NewGS, _} =
                    ar_gossip:send(GS, {new_block, Peer, Height, NewB, RecallB}),
                %ar:d([{block, NewB}, {hash_list, HashList}]),
                process_new_block(
                    S,
                    NewGS,
                    NewB,
                    RecallB,
                    Peer,
                    HashList
                );
            {replace_block_list, _NewBL = [B | _]} ->
                % Replace the entire stored block list, regenerating the hash list.
                %lists:map(fun ar_storage:write_block/1, NewBL),
                %ar:d({replaced, [B#block.indep_hash | B#block.hash_list]}),
                server(
                    S#state {
                        hash_list = [B#block.indep_hash | B#block.hash_list],
                        wallet_list = B#block.wallet_list,
                        height = B#block.height
                    }
                );
            {get_current_block, PID} ->
                PID ! {block, ar_util:get_head_block(HashList)},
                server(S);
            {get_blocks, PID} ->
                PID ! {blocks, self(), HashList},
                server(S);
            {get_block, PID} ->
                PID ! {block, self(), find_block(HashList)},
                server(S);
            {get_peers, PID} ->
                PID ! {peers, ar_gossip:peers(GS)},
                server(S);
            {get_trusted_peers, PID} ->
                PID ! {peers, S#state.trusted_peers},
                server(S);
            {get_walletlist, PID} ->
                PID ! {walletlist, S#state.wallet_list},
                server(S);
            {get_hashlist, PID} ->
                PID ! {hashlist, S#state.hash_list},
                server(S);
            {get_balance, PID, WalletID} ->
                PID ! {balance, WalletID,
                    case lists:keyfind(WalletID, 1, WalletList) of
                        {WalletID, Balance, _Last} -> Balance;
                        false -> 0
                    end},
                server(S);
            {get_last_tx, PID, Addr} ->
                PID ! {last_tx, Addr,
                    case lists:keyfind(Addr, 1, WalletList) of
                        {Addr, _Balance, Last} -> Last;
                        false -> <<>>
                    end},
                server(S);
            {get_last_tx_from_floating, PID, Addr} ->
                PID ! {last_tx_from_floating, Addr,
                case lists:keyfind(Addr, 1, FloatingWalletList) of
                    {Addr, _Balance, Last} -> Last;
                    false -> <<>>
                end},
                server(S);
            {get_txs, PID} ->
                PID ! {all_txs, S#state.txs ++ S#state.waiting_txs},
                server(S);
			{get_waiting_txs, PID} ->
				PID ! {waiting_txs, S#state.waiting_txs},
				server(S);
            {get_all_known_txs, PID} ->
                AllTX =
                    S#state.txs ++
                    S#state.waiting_txs ++
                    S#state.potential_txs,
                PID ! {all_known_txs, AllTX},
                server(S);
            {get_floatingwalletlist, PID} ->
                PID ! {floatingwalletlist, S#state.floating_wallet_list},
                server(S);
            {get_current_diff, PID} ->
                PID ! {
                    current_diff,
                    case ar_retarget:is_retarget_height(S#state.height + 1) of
                        true ->
                                ar_retarget:maybe_retarget(
                                S#state.height + 1,
                                S#state.diff,
                                os:system_time(seconds),
                                S#state.last_retarget
                            );
                        false -> S#state.diff
                    end
                },
                server(S);
            {get_diff, PID} ->
                PID ! {diff, S#state.diff},
                server(S);
            {get_reward_pool, PID} ->
                PID ! {reward_pool, S#state.reward_pool},
                server(S);
            {get_reward_addr, PID} ->
                PID ! {reward_addr, S#state.reward_addr},
                server(S);
            {set_reward_addr, Addr} ->
                server(S#state{reward_addr = Addr});
            mine ->
                server(start_mining(S));
            {mine_at_diff, Diff} ->
                server(start_mining(S, Diff));
            automine -> server(start_mining(S#state { automine = true }));
            {work_complete, MinedTXs, _Hash, Diff, Nonce, Timestamp} ->
                % The miner thinks it has found a new block
                case S#state.hash_list of
                    not_joined ->
                        do_nothing;
                    _ ->
                        integrate_block_from_miner(
                            S,
                            MinedTXs,
                            Diff,
                            Nonce,
                            Timestamp
                        )
                end;
            {add_peers, Ps} ->
                %ar:d({adding_peers, Ps}),
                server(S#state { gossip = ar_gossip:add_peers(GS, Ps) });
            stop ->
                case S#state.miner of
                    undefined -> do_nothing;
                    PID -> ar_mine:stop(PID)
                end,
                ok;
            {set_loss_probability, Prob} ->
                server(
                    S#state {
                        gossip =
                            ar_gossip:set_loss_probability(
                                S#state.gossip,
                                Prob
                            )
                    }
                );
            {set_delay, MaxDelay} ->
                server(
                    S#state {
                        gossip =
                            ar_gossip:set_delay(
                                S#state.gossip,
                                MaxDelay
                            )
                    }
                );
            {set_xfer_speed, Speed} ->
                server(
                    S#state {
                        gossip =
                            ar_gossip:set_xfer_speed(
                                S#state.gossip,
                                Speed
                            )
                    }
                );
            {set_mining_delay, Delay} ->
                server(
                    S#state {
                        mining_delay = Delay
                    }
                );
            {rejoin, Peers, Block} ->
                UntrustedPeers =
                    lists:filter(
                        fun(Peer) ->
                            not lists:member(Peer, S#state.trusted_peers)
                        end,
                        ar_util:unique(Peers)
                    ),
                lists:foreach(
                    fun(Peer) ->
                        ar_bridge:ignore_peer(whereis(http_bridge_node), Peer)
                    end,
                    UntrustedPeers
                ),
                ar_join:start(self(), S#state.trusted_peers, Block),
                server(S);
            {fork_recovered, NewHs} when HashList == not_joined ->
                NewB = ar_storage:read_block(hd(NewHs)),
                ar:report_console(
                    [
                        node_joined_successfully,
                        {height, NewB#block.height}
                    ]
                ),
                case whereis(fork_recovery_server) of
                    undefined -> ok;
                    _ -> erlang:unregister(fork_recovery_server)
                end,
                %ar_cleanup:remove_invalid_blocks(NewHs),
                TXPool = S#state.txs ++ S#state.potential_txs,
                TXs =
                    filter_all_out_of_order_txs(
                        NewB#block.wallet_list,
                        TXPool
                    ),
                PotentialTXs = TXPool -- TXs,
                server(
                    reset_miner(
                        S#state {
                            hash_list = NewHs,
                            wallet_list = NewB#block.wallet_list,
                            height = NewB#block.height,
                            reward_pool = NewB#block.reward_pool,
                            floating_wallet_list = NewB#block.wallet_list,
                            txs = TXs,
                            potential_txs = PotentialTXs,
                            diff = NewB#block.diff,
                            last_retarget = NewB#block.last_retarget,
                            weave_size = NewB#block.weave_size
                        }
                    )
                );
            {fork_recovered, NewHs}
                    when (length(NewHs)) >= (length(HashList)) ->
                case whereis(fork_recovery_server) of
                    undefined -> ok;
                    _ -> erlang:unregister(fork_recovery_server)
                end,
                NewB = ar_storage:read_block(hd(NewHs)),
                ar:report_console(
                    [
                        fork_recovered_successfully,
                        {height, NewB#block.height},
		    	{old_height, S#state.height}
                    ]
                ),
                %ar_cleanup:remove_invalid_blocks(NewHs),
                TXPool = S#state.txs ++ S#state.potential_txs,
                TXs =
                    filter_all_out_of_order_txs(
                        NewB#block.wallet_list,
                        TXPool
                    ),
                PotentialTXs = TXPool -- TXs,
                server(
                    reset_miner(
                        S#state {
                            hash_list =
                                [NewB#block.indep_hash | NewB#block.hash_list],
                            wallet_list = NewB#block.wallet_list,
                            height = NewB#block.height,
                            reward_pool = NewB#block.reward_pool,
                            floating_wallet_list = NewB#block.wallet_list,
                            txs = TXs,
                            potential_txs = PotentialTXs,
                            diff = NewB#block.diff,
                            last_retarget = NewB#block.last_retarget,
                            weave_size = NewB#block.weave_size
                        }
                    )
                );
            {fork_recovered, _} ->
		ar:report([discarding_fork_recovery, {reason, block_below_current}]),
		server(S);
            {'DOWN', _, _, _, _} ->
                server(S);
            Msg ->
                ar:report_console([{unknown_msg_node, Msg}]),
                server(S)
        end)
	catch
		throw:Term ->
			ar:report(
				[
					{'NodeEXCEPTION', {Term}}
				]
			),
			server(S);
		exit:Term ->
			ar:report(
				[
					{'NodeEXIT', Term}
				],
			server(S)
			);
		error:Term ->
			ar:report(
				[
					{'NodeERROR', {Term, erlang:get_stacktrace()}}
				]
			),
			server(S)
	end.

%%% Abstracted server functionality

%% @doc Catch up to the current height.
join_weave(S, NewB) ->
	ar_join:start(ar_gossip:peers(S#state.gossip), NewB),
	server(S).

%% @doc Recovery from a fork.
fork_recover(
	S = #state {
		hash_list = HashList,
		gossip = GS
	}, Peer, NewB) ->
	case {whereis(fork_recovery_server), whereis(join_server)} of
		{undefined, undefined} ->
			PrioritisedPeers = ar_util:unique(Peer) ++
				case whereis(http_bridge_node) of
					undefined -> [];
					BridgePID ->
						ar_bridge:get_remote_peers(BridgePID)
				end,
			erlang:monitor(
				process,
				PID = ar_fork_recovery:start(
					PrioritisedPeers,
					NewB,
					HashList
				)
			),
			case PID of
				undefined -> ok;
				_ -> erlang:register(fork_recovery_server, PID)
			end;
		{undefined, _} -> ok;
		_ ->
		whereis(fork_recovery_server) ! {update_target_block, NewB, ar_util:unique(Peer)}
	end,
	server(S).

%% @doc Return the sublist of shared starting elements from two lists.
%take_until_divergence([A | Rest1], [A | Rest2]) ->
%	[A | take_until_divergence(Rest1, Rest2)];
%take_until_divergence(_, _) -> [].

%% @doc Validate whether a new block is legitimate, then handle it, optionally
%% dropping or starting a fork recoverer as appropriate.
process_new_block(S, NewGS, NewB, _, _Peer, not_joined) ->
	join_weave(S#state { gossip = NewGS }, NewB);
process_new_block(RawS1, NewGS, NewB, unavailable, Peer, HashList)
		when NewB#block.height == RawS1#state.height + 1 ->
		% This block is at the correct height.
	RecallHash = find_recall_hash(NewB, HashList),
	FullBlock = ar_node:get_full_block(
		Peer,
		RecallHash
	),
	case ?IS_BLOCK(FullBlock) of
		true ->
			% TODO: Cleanup full block -> shadow generation.
			RecallShadow = FullBlock#block { txs = [T#tx.id || T <- FullBlock#block.txs] },
			ar_storage:write_full_block(FullBlock),
			S = RawS1#state { gossip = NewGS },
			process_new_block(S, NewGS, NewB, RecallShadow, Peer, HashList);
		false ->
			ar:d(failed_to_get_recall_block),
			server(RawS1)
	end;
process_new_block(RawS1, NewGS, NewB, RecallB, Peer, HashList)
		when NewB#block.height == RawS1#state.height + 1 ->
		% This block is at the correct height.
	S = RawS1#state { gossip = NewGS },
	% If transaction not found in state or storage, txlist built will be incomplete
	% and will fail in validate
	TXs = lists:foldr(
		fun(T, Acc) ->
			%state contains it
			case [TX || TX <- (S#state.txs ++ S#state.waiting_txs ++ S#state.potential_txs), TX#tx.id == T] of
				[] ->
					case ar_storage:read_tx(T) of
						unavailable ->
							Acc;
						TX -> [TX | Acc]
					end;
				[TX | _] -> [TX | Acc]
			end
		end,
		[],
		NewB#block.txs
	),
	{FinderReward, _} =
		calculate_reward_pool(
			S#state.reward_pool,
			TXs,
			NewB#block.reward_addr,
			calculate_proportion(
				RecallB#block.block_size,
				NewB#block.weave_size,
				NewB#block.height
			)
		),
	WalletList =
		apply_mining_reward(
			apply_txs(S#state.wallet_list, TXs),
			NewB#block.reward_addr,
			FinderReward,
			NewB#block.height
		),
	NewS = S#state { wallet_list = WalletList },
	case validate(NewS, NewB, TXs, ar_util:get_head_block(HashList), RecallB) of
		true ->
			% The block is legit. Accept it.
			case whereis(fork_recovery_server) of
				undefined -> integrate_new_block(NewS, NewB);
				_ -> fork_recover(S#state { gossip = NewGS }, Peer, NewB)
			end;
		false ->
			ar:report(
				[
					{could_not_validate_new_block, ar_util:encode(NewB#block.indep_hash)},
					{height, NewB#block.height},
					attempting_fork_recovery
				]
			),
			%server(S)
			fork_recover(S, Peer, NewB)
	end;
process_new_block(S, NewGS, NewB, _RecallB, _Peer, _HashList)
		when NewB#block.height =< S#state.height ->
	% Block is lower than us, ignore it.
	ar:report(
		[
			{ignoring_block_below_current, ar_util:encode(NewB#block.indep_hash)},
			{current_height, S#state.height},
			{proposed_block_height, NewB#block.height}
		]
	),
	server(S#state { gossip = NewGS });
% process_new_block(S, NewGS, NewB, _RecallB, _Peer, _Hashlist)
% 		when (NewB#block.height == S#state.height + 1) ->
	% Block is lower than fork recovery height, ignore it.
	% server(S#state { gossip = NewGS });
process_new_block(S, NewGS, NewB, _, Peer, _HashList)
		when (NewB#block.height > S#state.height + 1) ->
	fork_recover(S#state { gossip = NewGS }, Peer, NewB).

%% @doc We have received a new valid block. Update the node state accordingly.
integrate_new_block(
		S = #state {
			txs = TXs,
			hash_list = HashList,
			wallet_list = WalletList,
			waiting_txs = WaitingTXs,
			potential_txs = PotentialTXs
		},
		NewB) ->
	% Filter completed TXs from the pending list.
	Diff = ar_mine:next_diff(NewB),
	RawKeepNotMinedTXs =
		lists:filter(
			fun(T) ->
                (not ar_weave:is_tx_on_block_list([NewB], T#tx.id)) and
				ar_tx:verify(T, Diff, WalletList)
			end,
			TXs
		),
	NotMinedTXs =
		lists:filter(
			fun(T) ->
                (not ar_weave:is_tx_on_block_list([NewB], T#tx.id))
			end,
			TXs ++ WaitingTXs ++ PotentialTXs
		),
	KeepNotMinedTXs = filter_all_out_of_order_txs(NewB#block.wallet_list, RawKeepNotMinedTXs),
	BlockTXs = (TXs ++ WaitingTXs ++ PotentialTXs) -- NotMinedTXs,
	% Write new block and included TXs to local storage.
	ar_storage:write_tx(BlockTXs),
	ar_storage:write_block(NewB),
	% Recurse over the new block.
	ar:report_console(
		[
			{accepted_foreign_block, ar_util:encode(NewB#block.indep_hash)},
			{height, NewB#block.height}
		]
	),
	%ar:d({new_hash_list, [NewB#block.indep_hash | HashList]}),
	app_search:update_tag_table(NewB),
	lists:foreach(
		fun(T) ->
			ar_tx_db:maybe_add(T#tx.id)
		end,
		PotentialTXs
	),
	RecallB =
		ar_node:get_full_block(
			whereis(http_entrypoint_node),
			find_recall_hash(NewB, [NewB#block.indep_hash | HashList])
		),
	case ?IS_BLOCK(RecallB) of
		true ->
			ar_key_db:put(
				RecallB#block.indep_hash,
				[
					{
						ar_block:generate_block_key(RecallB, NewB#block.previous_block),
						binary:part(NewB#block.indep_hash, 0, 16)
					}
				]
			);
		false -> ok
	end,
	server(
		reset_miner(
			S#state {
				hash_list = [NewB#block.indep_hash | HashList],
				txs = ar_track_tx_db:remove_bad_txs(KeepNotMinedTXs),
				height = NewB#block.height,
				floating_wallet_list = apply_txs(WalletList, TXs),
				reward_pool = NewB#block.reward_pool,
				potential_txs = [],
				diff = NewB#block.diff,
				last_retarget = NewB#block.last_retarget,
				weave_size = NewB#block.weave_size
			}
		)
	).

%% @doc Verify a new block found by a miner, integrate it.
integrate_block_from_miner(
		OldS = #state {
			hash_list = HashList,
			wallet_list = RawWalletList,
			txs = TXs,
			gossip = GS,
            reward_addr = RewardAddr,
            tags = Tags,
			reward_pool = OldPool,
			weave_size = OldWeaveSize
		},
		MinedTXs, Diff, Nonce, Timestamp) ->
	% Calculate the new wallet list (applying TXs and mining rewards).
    RecallB = ar_node:find_recall_block(HashList),
    WeaveSize = OldWeaveSize +
        lists:foldl(
            fun(TX, Acc) ->
                Acc + byte_size(TX#tx.data)
            end,
            0,
            TXs
		),
	{FinderReward, RewardPool} =
		calculate_reward_pool(
			OldPool,
			MinedTXs,
			RewardAddr,
			calculate_proportion(
				RecallB#block.block_size,
				WeaveSize,
				length(HashList)
			)
		),
	ar:report(
		[
			calculated_reward_for_mined_block,
			{finder_reward, FinderReward},
			{new_reward_pool, RewardPool},
			{reward_address, RewardAddr},
			{old_reward_pool, OldPool},
			{txs, length(MinedTXs)},
			{recall_block_size, RecallB#block.block_size},
			{weave_size, WeaveSize},
			{length, length(HashList)}
		]
	),
	WalletList =
		apply_mining_reward(
			apply_txs(RawWalletList, MinedTXs),
			RewardAddr,
			FinderReward,
			length(HashList)
		),
	% Store the transactions that we know about, but were not mined in
	% this block.
	NotMinedTXs =
		lists:filter(
			fun(T) -> ar_tx:verify(T, Diff, WalletList) end,
			filter_all_out_of_order_txs(WalletList, TXs -- MinedTXs)
		),
    NewS = OldS#state { wallet_list = WalletList },
    % Build the block record, verify it, and gossip it to the other nodes.
	[NextB | _] =
		ar_weave:add(HashList, MinedTXs, HashList, RewardAddr, RewardPool, WalletList, Tags, RecallB, Diff, Nonce, Timestamp),
		%ar:d({validate,validate(NewS, NextB, MinedTXs, ar_util:get_head_block(HashList), RecallB = find_recall_block(HashList))}),
	case validate(NewS, NextB, MinedTXs, ar_util:get_head_block(HashList), RecallB = find_recall_block(HashList)) of
		false ->
			ar:report_console(miner_produced_invalid_block),
			case rand:uniform(5) of
				1 ->
					server(
						reset_miner(
							OldS#state {
								gossip = NewS#state.gossip,
								txs = [], % TXs not included in the block
								potential_txs = []
							}
						)
					);
				_ -> server(
					reset_miner(OldS)
				)
			end;
		true ->
			ar_storage:write_tx(MinedTXs),
			ar_storage:write_block(NextB),
			app_search:update_tag_table(NextB),
			{NewGS, _} =
				ar_gossip:send(
					GS,
					{
						new_block,
						self(),
						NextB#block.height,
						NextB,
						RecallB
					}
				),
			ar:report_console(
				[
					{node, self()},
					{accepted_block, NextB#block.height},
					{indep_hash, ar_util:encode(NextB#block.indep_hash)},
					{recall_block, RecallB#block.height},
					{recall_hash, RecallB#block.indep_hash},
					{txs, length(MinedTXs)},
					case is_atom(RewardAddr) of
						true -> {reward_address, unclaimed};
						false -> {reward_address, ar_util:encode(RewardAddr)}
					end
				]
			),
			lists:foreach(
				fun(MinedTX) ->
					ar:report(
						{successfully_mined_tx_into_block, ar_util:encode(MinedTX#tx.id)}
					)
				end,
				MinedTXs
			),
			lists:foreach(
				fun(T) ->
					ar_tx_db:maybe_add(T#tx.id)
				end,
				OldS#state.potential_txs
			),
			server(
				reset_miner(
					NewS#state {
						gossip = NewGS,
						hash_list =
							[NextB#block.indep_hash | HashList],
						txs = ar_track_tx_db:remove_bad_txs(NotMinedTXs), % TXs not included in the block
						height = NextB#block.height,
						floating_wallet_list = apply_txs(WalletList, NotMinedTXs),
						reward_pool = RewardPool,
						potential_txs = [],
						diff = NextB#block.diff,
						last_retarget = NextB#block.last_retarget,
						weave_size = NextB#block.weave_size
					}
				)
			)
	end.

%% @doc Update miner and amend server state when encountering a new transaction.
add_tx_to_server(S, NewGS, TX) ->
    memsup:start_link(),
    {_, Mem} = lists:keyfind(
        system_total_memory,
        1,
        memsup:get_system_memory_data()
    ),
    case (Mem div 4) > byte_size(TX#tx.data) of
        true ->
            NewTXs = S#state.txs ++ [TX],
	        %ar:d({added_tx, TX#tx.id}),
	        server(S#state {
				txs = NewTXs,
				floating_wallet_list = apply_tx(S#state.floating_wallet_list, TX),
				gossip = NewGS,
				waiting_txs = (S#state.waiting_txs -- [TX]) });
        false ->
            server(S#state { gossip = NewGS , waiting_txs = (S#state.waiting_txs -- [TX]) })
    end.

%% @doc Validate a new block, given a server state, a claimed new block, the last block,
%% and the recall block.
validate(_, _, _, _, _, unavailable, _, _) -> false;
validate(
		HashList,
		WalletList,
		NewB =
			#block {
				hash_list = HashList,
				wallet_list = WalletList,
                nonce = Nonce,
				diff = Diff,
				timestamp = Timestamp
			},
		TXs,
		OldB,
        RecallB,
        RewardAddr,
        Tags) ->
    % ar:d([{hl, HashList}, {wl, WalletList}, {newb, NewB}, {oldb, OldB}, {recallb, RecallB}]),
	%ar:d({node, ar_weave:hash(ar_block:generate_block_data_segment(OldB, RecallB, TXs, RewardAddr, Timestamp, Tags), Nonce), Nonce, Diff}),
	% TODO: Fix names
    Mine = ar_mine:validate(ar_block:generate_block_data_segment(OldB, RecallB, TXs, RewardAddr, Timestamp, Tags), Nonce, Diff),
    Wallet = validate_wallet_list(WalletList),
    IndepRecall = ar_weave:verify_indep(RecallB, HashList),
    Txs = ar_tx:verify_txs(TXs, Diff, OldB#block.wallet_list),
    Retarget = ar_retarget:validate(NewB, OldB),
    IndepHash = ar_block:verify_indep_hash(NewB),
	Hash = ar_block:verify_dep_hash(NewB, OldB, RecallB, TXs),
	WeaveSize = ar_block:verify_weave_size(NewB, OldB, TXs),
	Size = ar_block:block_field_size_limit(NewB),
	%Time = ar_block:verify_timestamp(OldB, NewB),
	HeightCheck = ar_block:verify_height(NewB, OldB),
	RetargetCheck = ar_block:verify_last_retarget(NewB),
	PreviousBCheck = ar_block:verify_previous_block(NewB, OldB),
	HashlistCheck = ar_block:verify_block_hash_list(NewB, OldB),
	WalletListCheck = ar_block:verify_wallet_list(NewB, OldB, RecallB, TXs),


	ar:report(
		[
			{validate_block, ar_util:encode(NewB#block.indep_hash)},
			{height, NewB#block.height},
			{block_mine_validate, Mine},
			{block_wallet_validate, Wallet},
			{block_indep_validate, IndepRecall},
			{block_txs_validate, Txs},
			{block_diff_validate, Retarget},
			{block_indep, IndepHash},
			{block_hash, Hash},
			{weave_size, WeaveSize},
			{block_size, Size},
			{block_height, HeightCheck},
			{block_retarget_time, RetargetCheck},
			{block_previous_check, PreviousBCheck},
			{block_hash_list, HashlistCheck},
			{block_wallet_list ,WalletListCheck}
		]
	),

	case IndepRecall of
		false ->
			ar:d(
				[
					{encountered_invalid_recall_block, ar_util:encode(RecallB#block.indep_hash)},
					moving_to_invalid_block_directory
				]
			),
			ar_storage:invalidate_block(RecallB);
		_ ->
			ok
	end,

	case Mine of false -> ar:d(invalid_nonce); _ -> ok end,
	case Wallet of false -> ar:d(invalid_wallet_list); _ -> ok  end,
	case Txs of false -> ar:d(invalid_txs); _ -> ok  end,
    case Retarget of false -> ar:d(invalid_difficulty); _ -> ok  end,
    case IndepHash of false -> ar:d(invalid_indep_hash); _ -> ok  end,
	case Hash of false -> ar:d(invalid_dependent_hash); _ -> ok  end,
	case WeaveSize of false -> ar:d(invalid_total_weave_size); _ -> ok  end,
    case Size of false -> ar:d(invalid_size); _ -> ok  end,
 	case HeightCheck of false -> ar:d(invalid_height); _ -> ok  end,
	case RetargetCheck of false -> ar:d(invalid_retarget); _ -> ok  end,
	case PreviousBCheck of false -> ar:d(invalid_previous_block); _ -> ok  end,
	case HashlistCheck of false -> ar:d(invalid_hash_list); _ -> ok  end,
	case WalletListCheck of false -> ar:d(invalid_wallet_list_rewards); _ -> ok  end,

	(Mine =/= false)
		andalso Wallet
		andalso IndepRecall
		andalso Txs
		andalso Retarget
        andalso IndepHash
        andalso Hash
		andalso WeaveSize
        andalso Size
		andalso HeightCheck
		andalso RetargetCheck
		andalso PreviousBCheck
		andalso HashlistCheck
		andalso WalletListCheck;
validate(_HL, WL, NewB = #block { hash_list = undefined }, TXs, OldB, RecallB, _, _) ->
	validate(undefined, WL, NewB, TXs, OldB, RecallB, unclaimed, []);
validate(HL, _WL, NewB = #block { wallet_list = undefined }, TXs,OldB, RecallB, _, _) ->
	validate(HL, undefined, NewB, TXs, OldB, RecallB, unclaimed, []);
validate(_HL, _WL, _NewB, _TXs, _OldB, _RecallB, _, _) ->
	% ar:d({val_hashlist, _NewB#block.hash_list}),
	% ar:d({val_wallet_list, _NewB#block.wallet_list}),
	% ar:d({val_nonce, _NewB#block.nonce}),
	% ar:d({val_hash, _OldB#block.hash_list}),
	% ar:d({val_diff, _OldB#block.diff}),
	% ar:d({hashlist, _HL}),
	% ar:d({wallet_list, _WL}),
	% ar:d({txs, _TXs}),
	% ar:d({recall, _RecallB}),
	ar:d(block_not_accepted),
	false.

%% @doc Validate a block, given a node state and the dependencies.
validate(#state { hash_list = HashList, wallet_list = WalletList }, B, TXs, OldB, RecallB) ->
	validate(HashList, WalletList, B, TXs, OldB, RecallB, B#block.reward_addr, B#block.tags).

%% @doc Ensure that all wallets in the wallet list have a positive balance.
validate_wallet_list([]) -> true;
validate_wallet_list([{_, 0, Last} | _]) when byte_size(Last) == 0 -> false;
validate_wallet_list([{_, Qty, _} | _]) when Qty < 0 -> false;
validate_wallet_list([_ | Rest]) -> validate_wallet_list(Rest).

%% @doc Update the wallet list of a server with a set of new transactions
apply_txs(S, TXs) when is_record(S, state) ->
	S#state {
		wallet_list = apply_txs(S#state.wallet_list, TXs)
	};
apply_txs(WalletList, TXs) ->
	lists:sort(
		lists:foldl(
			fun(TX, CurrWalletList) ->
				apply_tx(CurrWalletList, TX)
			end,
			WalletList,
			TXs
		)
	).

calculate_reward_pool(OldPool, TXs, unclaimed, _Proportion) ->
	Pool = OldPool + lists:sum(
		lists:map(
			fun calculate_tx_reward/1,
			TXs
		)
	),
	{0, Pool};
calculate_reward_pool(OldPool, TXs, _RewardAddr, Proportion) ->
	Pool = OldPool + lists:sum(
		lists:map(
			fun calculate_tx_reward/1,
			TXs
		)
	),
	FinderReward = erlang:trunc(Pool * Proportion),
	{FinderReward, Pool - FinderReward}.

%% @doc Calculate and apply mining reward quantities to a wallet list.
apply_mining_reward(WalletList, unclaimed, _Quantity, _Height) -> WalletList;
apply_mining_reward(WalletList, RewardAddr, Quantity, Height) ->
    % ar:d({WalletList}),
    % ar:d({RewardAddr}),
    % ar:d({TXs}),
    % ar:d({Height}),
	alter_wallet(WalletList, RewardAddr, calculate_reward(Height, Quantity)).

%% @doc Apply a transaction to a wallet list, updating it.
%% Critically, filter empty wallets from the list after application.
apply_tx(WalletList, unavailable) ->
	WalletList;
apply_tx(WalletList, TX) ->
	filter_empty_wallets(do_apply_tx(WalletList, TX)).

do_apply_tx(
		WalletList,
		#tx {
			id = ID,
			owner = From,
			last_tx = Last,
			target = To,
			quantity = Qty,
			reward = Reward
		}) ->
	Addr = ar_wallet:to_address(From),
	case lists:keyfind(Addr, 1, WalletList) of
		{Addr, Balance, Last} ->
			NewWalletList = lists:keyreplace(Addr, 1, WalletList, {Addr, Balance - (Qty + Reward), ID}),
			case lists:keyfind(To, 1, NewWalletList) of
				false -> [{To, Qty, <<>>} | NewWalletList];
				{To, OldBalance, LastTX} ->
					lists:keyreplace(To, 1, NewWalletList, {To, OldBalance + Qty, LastTX})
			end;
		_ ->
			%ar:report([{ignoring_tx, ID}, starting_wallet_not_instantiated]),
			WalletList
	end.

%% @doc Remove wallets with zero balance from a wallet list.
filter_empty_wallets([]) -> [];
filter_empty_wallets([{_, 0, <<>>} | WalletList]) -> filter_empty_wallets(WalletList);
filter_empty_wallets([Wallet | Rest]) -> [Wallet | filter_empty_wallets(Rest)].

%% @doc Alter a wallet in a wallet list.
alter_wallet(WalletList, Target, Adjustment) ->
	case lists:keyfind(Target, 1, WalletList) of
		false ->
			%io:format("~p: Could not find pub ~p in ~p~n", [self(), Target, WalletList]),
			[{Target, Adjustment, <<>>}|WalletList];
		{Target, Balance, LastTX} ->
			%io:format(
			%	"~p: Target: ~p Balance: ~p Adjustment: ~p~n",
			%	[self(), Target, Balance, Adjustment]
			%),
			lists:keyreplace(
				Target,
				1,
				WalletList,
				{Target, Balance + Adjustment, LastTX}
			)
	end.

%% @doc Search a block list for the next recall block.
find_recall_block([H]) -> ar_storage:read_block(H);
find_recall_block(HashList) ->
	B = ar_storage:read_block(hd(HashList)),
	RecallHash = find_recall_hash(B, HashList),
	ar_storage:read_block(RecallHash).

%% @doc Return the hash of the next recall block.
find_recall_hash(B, []) ->
	B#block.indep_hash;
find_recall_hash(B, HashList) ->
	lists:nth(1 + ar_weave:calculate_recall_block(B), lists:reverse(HashList)).
%% @doc Find a block from an ordered block list.
find_block(Hash) when is_binary(Hash) ->
	ar_storage:read_block(Hash).

%% @doc Returns the last block to include both a wallet and hash list.
find_sync_block([]) -> not_found;
find_sync_block([Hash | Rest]) when is_binary(Hash) ->
	find_sync_block([ar_storage:read_block(Hash) | Rest]);
find_sync_block([B = #block { hash_list = HashList, wallet_list = WalletList } | _])
		when HashList =/= undefined, WalletList =/= undefined -> B;
find_sync_block([_ | Xs]) -> find_sync_block(Xs).

%% @doc Calculate the total mining reward for the a block and it's associated TXs.
%calculate_reward(B) -> calculate_reward(B#block.height, B#block.txs).
calculate_reward(Height, Quantity) ->
	erlang:trunc(calculate_static_reward(Height) + Quantity).

%% @doc Calculate the static reward received for mining a given block.
%% This reward portion depends only on block height, not the number of transactions.
calculate_static_reward(Height) when Height =< ?REWARD_DELAY-> 1;
calculate_static_reward(Height) ->
	?AR((0.2 * ?GENESIS_TOKENS * math:pow(2,-(Height-?REWARD_DELAY)/?BLOCK_PER_YEAR) * math:log(2))/?BLOCK_PER_YEAR).
%% @doc Given a TX, calculate an appropriate reward.
calculate_tx_reward(#tx { reward = Reward }) ->
	Reward.

%% @doc Kill the old miner, optionally start a new miner, depending on the automine setting.
reset_miner(S = #state { miner = undefined, automine = false }) -> S;
reset_miner(S = #state { miner = undefined, automine = true }) ->
	start_mining(S);
reset_miner(S = #state { miner = PID, automine = false }) ->
	ar_mine:stop(PID),
	S#state { miner = undefined };
reset_miner(S = #state { miner = PID, automine = true }) ->
	ar_mine:stop(PID),
	start_mining(S#state { miner = undefined }).

%% @doc Force a node to start mining, update state.
start_mining(S) -> start_mining(S, unforced).
start_mining(S = #state { hash_list = not_joined }, _) ->
	% We don't have a block list. Wait until we have one before
	% starting to mine.
	S;
start_mining(S = #state { hash_list = BHL, txs = TXs, reward_addr = RewardAddr, tags = Tags }, ForceDiff) ->
	case find_recall_block(BHL) of
		unavailable ->
			B = ar_storage:read_block(hd(BHL)),
			RecallHash = find_recall_hash(B, BHL),
			%FullBlock = get_encrypted_full_block(ar_bridge:get_remote_peers(whereis(http_bridge_node)), RecallHash),
			FullBlock = get_full_block(ar_bridge:get_remote_peers(whereis(http_bridge_node)), RecallHash),
			case FullBlock of
				X when (X == unavailable) or (X == not_found) ->
					ar:report(
						[
							could_not_start_mining,
							could_not_retrieve_recall_block
						]
					);
				_ ->
					case ar_weave:verify_indep(FullBlock, BHL) of
						true ->
							ar_storage:write_full_block(FullBlock),
							ar:report(
								[
									could_not_start_mining,
									stored_recall_block_for_foreign_verification
								]
							);
						false ->
								ar:report(
									[
										could_not_start_mining,
										{received_invalid_recall_block, FullBlock#block.indep_hash}
									]
								)
					end
			end,
			S;
		RecallB ->
			if not is_record(RecallB, block) ->
				ar:report_console([{erroneous_recall_block, RecallB}]);
			true ->
				ar:report([{node_starting_miner, self()}, {recall_block, RecallB#block.height}])
			end,
			RecallBFull = make_full_block(
				RecallB#block.indep_hash
			),
			ar_key_db:put(
				RecallB#block.indep_hash,
				[
					{
						ar_block:generate_block_key(RecallBFull, hd(BHL)),
						binary:part(hd(BHL), 0, 16)
					}
				]
			),
			B = ar_storage:read_block(hd(BHL)),
			case ForceDiff of
				unforced ->
					Miner = ar_mine:start(
						B,
						RecallB,
						TXs,
						RewardAddr,
						Tags
					),
					ar:report([{node, self()}, {started_miner, Miner}]),
					S#state { miner = Miner };
				ForceDiff ->
					Miner = ar_mine:start(
						B,
						RecallB,
						TXs,
						RewardAddr,
						Tags,
						ForceDiff
					),
					ar:report([{node, self()}, {started_miner, Miner}, {forced_diff, ForceDiff}]),
					S#state { miner = Miner, diff = ForceDiff }
			end
	end.

%% @doc Calculate the time a tx must wait after being received to be mined.
%% Wait time is a fixed interval combined with a wait dependent on tx data size.
%% This wait helps ensure that a tx has propogated around the network.
%% NB: If debug is defined no wait is applied.
-ifdef(DEBUG).
-define(FIXED_DELAY, 0).
-endif.

-ifdef(FIXED_DELAY).
calculate_delay(0) -> ?FIXED_DELAY;
calculate_delay(Bytes) -> ?FIXED_DELAY.
-else.
calculate_delay(0) ->
    30000;
calculate_delay(Bytes) ->
    30000 + ((Bytes * 300) div 1000).
-endif.

%% @doc Calculates the portion of the rewardpool that the miner is entitled
%% to for mining a block with a given Recall.
%% The proportion is based on the size of the recall block and the average data
%% stored within the weave.
calculate_proportion(RecallSize, WeaveSize, Height)
        when (Height == 0)->
    % Genesis block
	calculate_proportion(
        RecallSize,
        WeaveSize,
        1
    );
calculate_proportion(RecallSize, WeaveSize, Height)
        when (WeaveSize == 0)->
    % No data stored in the weave
	calculate_proportion(
        RecallSize,
        1,
        Height
    );
calculate_proportion(RecallSize, WeaveSize, Height)
        when RecallSize >= (WeaveSize/Height) ->
    % Recall size is larger than the average data stored per block
	XRaw = ((Height * RecallSize) / WeaveSize) - 1,
	X = min(XRaw, 1023),
	max(
        0.1,
        (math:pow(2, X) / (math:pow(2, X) + 2))
    );
calculate_proportion(RecallSize, WeaveSize, Height)
        when RecallSize == 0 ->
    % Recall block has no data txs, hence size of zero
    calculate_proportion(
        1,
        WeaveSize,
        Height
    );
calculate_proportion(RecallSize, WeaveSize, Height) ->
    % Standard recall block, 0 < Recall size < Average block
	XRaw = -(((Height * WeaveSize) / RecallSize) -1),
	X = min(XRaw, 1023),
	max(
        0.1,
        (math:pow(2, X)/(math:pow(2, X) + 2))
    ).

%% @doc Given a wallet list and set of txs will try to apply the txs
%% iteratively to the wallet list and return the result.
%% Txs that cannot be applied are disregarded.
generate_floating_wallet_list(WalletList, []) ->
	WalletList;
generate_floating_wallet_list(WalletList, [T | TXs]) ->
	case ar_tx:check_last_tx(WalletList, T) of
		true ->
			UpdatedWalletList = apply_tx(WalletList, T),
			generate_floating_wallet_list(UpdatedWalletList, TXs);
		false -> false
	end.

%% @doc Takes a wallet list and a set of txs and checks to ensure that the
%% txs can be applied in a given order. The output is the set of all txs
%% that could be applied.
filter_all_out_of_order_txs(WalletList, InTXs) ->
	filter_all_out_of_order_txs(
        WalletList,
        InTXs,
        []
    ).
filter_all_out_of_order_txs(_WalletList, [], OutTXs) ->
	lists:reverse(OutTXs);
filter_all_out_of_order_txs(WalletList, InTXs, OutTXs) ->
    {FloatingWalletList, PassedTXs} =
        filter_out_of_order_txs(
            WalletList,
            InTXs,
            OutTXs
        ),
	RemainingInTXs = InTXs -- PassedTXs,
	case PassedTXs of
		[] ->
            lists:reverse(OutTXs);
		OutTXs ->
            lists:reverse(OutTXs);
		_ ->
            filter_all_out_of_order_txs(
                FloatingWalletList,
                RemainingInTXs,
                PassedTXs
            )
    end.

%% @doc Takes a wallet list and a set of txs and checks to ensure that the
%% txs can be iteratively applied. When a tx is encountered that cannot be
%% applied it is disregarded. The return is a tuple containing the output
%% wallet list and the set of applied transactions.
%% Helper function for 'filter_all_out_of_order_txs'.
filter_out_of_order_txs(WalletList, InTXs) ->
	filter_out_of_order_txs(
        WalletList,
        InTXs,
        []
    ).
filter_out_of_order_txs(WalletList, [], OutTXs) ->
	{WalletList, OutTXs};
filter_out_of_order_txs(WalletList, [T | RawTXs], OutTXs) ->
	case ar_tx:check_last_tx(WalletList, T) of
		true ->
			UpdatedWalletList = apply_tx(WalletList, T),
			filter_out_of_order_txs(
                UpdatedWalletList,
                RawTXs,
                [T | OutTXs]
            );
		false ->
			filter_out_of_order_txs(
                WalletList,
                RawTXs,
                OutTXs
            )
	end.


%%% Tests: ar_node

%% @doc Run a small, non-auto-mining blockweave. Mine blocks.
tiny_network_with_reward_pool_test() ->
	ar_storage:clear(),
	B0 = ar_weave:init([], ?DEFAULT_DIFF, ?AR(1)),
	Node1 = start([], B0),
	ar_storage:write_block(B0),
	Node2 = start([Node1], B0),
	ar_node:set_reward_addr(Node1, << 0:256 >>),
	receive after 500 -> ok end,
	add_peers(Node1, Node2),
	mine(Node1),
	receive after 1000 -> ok end,
	mine(Node1),
	receive after 1000 -> ok end,
	B2 = get_blocks(Node2),
	2 = (hd(ar_storage:read_block(B2)))#block.height.

%% @doc Ensure that a set of txs can be checked for serialization, those that
%% don't serialize disregarded.
filter_out_of_order_txs_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	RawTX = ar_tx:new(Pub2, ?AR(1), ?AR(500), <<>>),
	TX = RawTX#tx {owner = Pub1},
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	RawTX2 = ar_tx:new(Pub3, ?AR(1), ?AR(400), SignedTX#tx.id),
	TX2 = RawTX2#tx {owner = Pub1},
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	WalletList =
		[
			{ar_wallet:to_address(Pub1), ?AR(1000), <<>>},
			{ar_wallet:to_address(Pub2), ?AR(2000), <<>>},
			{ar_wallet:to_address(Pub3), ?AR(3000), <<>>}
        ],
    % TX1 applied, TX2 applied
    {_, [SignedTX2, SignedTX]} =
        filter_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX2]
            ),
    % TX2 disregarded, TX1 applied
    {_, [SignedTX]} =
        filter_out_of_order_txs(
                WalletList,
                [SignedTX2, SignedTX]
            ).

%% @doc Ensure that a large set of txs can be checked for serialization,
%% those that don't serialize disregarded.
filter_out_of_order_txs_large_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(500), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = ar_tx:new(Pub3, ?AR(1), ?AR(400), SignedTX#tx.id),
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	TX3 = ar_tx:new(Pub3, ?AR(1), ?AR(50), SignedTX2#tx.id),
	SignedTX3 = ar_tx:sign(TX3, Priv1, Pub1),
	WalletList =
		[
			{ar_wallet:to_address(Pub1), ?AR(1000), <<>>},
			{ar_wallet:to_address(Pub2), ?AR(2000), <<>>},
			{ar_wallet:to_address(Pub3), ?AR(3000), <<>>}
        ],
    % TX1 applied, TX2 applied, TX3 applied
    {_, [SignedTX3, SignedTX2, SignedTX]} =
        filter_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX2, SignedTX3]
            ),
    % TX2 disregarded, TX3 disregarded, TX1 applied
    {_, [SignedTX]} =
        filter_out_of_order_txs(
                WalletList,
                [SignedTX2, SignedTX3, SignedTX]
            ),
    % TX1 applied, TX3 disregarded, TX2 applied.
    {_, [SignedTX2, SignedTX]} =
        filter_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX3, SignedTX2]
            ).

%% @doc Ensure that a set of txs can be serialized in the best possible order.
filter_all_out_of_order_txs_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(500), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = ar_tx:new(Pub3, ?AR(1), ?AR(400), SignedTX#tx.id),
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	WalletList =
		[
			{ar_wallet:to_address(Pub1), ?AR(1000), <<>>},
			{ar_wallet:to_address(Pub2), ?AR(2000), <<>>},
			{ar_wallet:to_address(Pub3), ?AR(3000), <<>>}
        ],
    % TX1 applied, TX2 applied
    [SignedTX, SignedTX2] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX2]
            ),
    % TX2 applied, TX1 applied
    [SignedTX, SignedTX2] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX2, SignedTX]
            ).

%% @doc Ensure that a large set of txs can be serialized in the best
%% possible order.
filter_all_out_of_order_txs_large_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(500), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = ar_tx:new(Pub3, ?AR(1), ?AR(400), SignedTX#tx.id),
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	TX3 = ar_tx:new(Pub3, ?AR(1), ?AR(50), SignedTX2#tx.id),
    SignedTX3 = ar_tx:sign(TX3, Priv1, Pub1),
    TX4 = ar_tx:new(Pub1, ?AR(1), ?AR(25), <<>>),
    SignedTX4 = ar_tx:sign(TX4, Priv2, Pub2),
	WalletList =
		[
			{ar_wallet:to_address(Pub1), ?AR(1000), <<>>},
			{ar_wallet:to_address(Pub2), ?AR(2000), <<>>},
			{ar_wallet:to_address(Pub3), ?AR(3000), <<>>}
        ],
    % TX1 applied, TX2 applied, TX3 applied
    [SignedTX, SignedTX2, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX2, SignedTX3]
            ),
    % TX1 applied, TX3 applied, TX2 applied
    [SignedTX, SignedTX2, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX3, SignedTX2]
            ),
    % TX2 applied, TX1 applied, TX3 applied
    [SignedTX, SignedTX2, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX2, SignedTX, SignedTX3]
            ),
    % TX2 applied, TX3 applied, TX1 applied
    [SignedTX, SignedTX2, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX2, SignedTX3, SignedTX]
            ),
    % TX3 applied, TX1 applied, TX2 applied
    [SignedTX, SignedTX2, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX3, SignedTX, SignedTX2]
            ),
    % TX3 applied, TX2 applied, TX1 applied
    [SignedTX, SignedTX2, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX3, SignedTX2, SignedTX]
            ),
    % TX1 applied, TX1 duplicate, TX1 duplicate, TX2 applied, TX4 applied
    % TX1 duplicate, TX3 applied
    % NB: Consider moving into separate test.
    [SignedTX, SignedTX2, SignedTX4, SignedTX3] =
        filter_all_out_of_order_txs(
                WalletList,
                [SignedTX, SignedTX, SignedTX, SignedTX2, SignedTX4, SignedTX, SignedTX3]
            ).

%% @doc Check the current block can be retrieved
get_current_block_test() ->
	ar_storage:clear(),
	[B0] = ar_weave:init(),
	Node = ar_node:start([], [B0]),
	B0 = get_current_block(Node).

%% @doc Check that blocks can be added (if valid) by external processes.
add_block_test() ->
	ar_storage:clear(),
	[B0] = ar_weave:init(),
	Node1 = ar_node:start([], [B0]),
    [B1 | _] = ar_weave:add([B0]),
	add_block(Node1, B1, B0),
    receive after 500 -> ok end,
    Blocks = lists:map(fun(B) -> B#block.indep_hash end, [B1, B0]),
    Blocks = get_blocks(Node1).

%% @doc Ensure that bogus blocks are not accepted onto the network.
add_bogus_block_test() ->
    ar_storage:clear(),
    ar_storage:write_tx(
        [
            TX1 = ar_tx:new(<<"HELLO WORLD">>),
            TX2 = ar_tx:new(<<"NEXT BLOCK.">>)
        ]
    ),
    Node = ar_node:start(),
    GS0 = ar_gossip:init([Node]),
    B0 = ar_weave:init([]),
    ar_storage:write_block(B0),
    B1 = ar_weave:add(B0, [TX1]),
    LastB = hd(B1),
    ar_storage:write_block(hd(B1)),
    BL = [hd(B1), hd(B0)],
    Node ! {replace_block_list, BL},
    B2 = ar_weave:add(B1, [TX2]),
    ar_storage:write_block(hd(B2)),
    ar_gossip:send(GS0,
        {
            new_block,
            self(),
            (hd(B2))#block.height,
            (hd(B2))#block { hash = <<"INCORRECT">> },
            find_recall_block(B2)
        }),
    receive after 500 -> ok end,
    Node ! {get_blocks, self()},
    receive
        {blocks, Node, [RecvdB | _]} ->
			LastB = ar_storage:read_block(RecvdB)
    end.

%% @doc Ensure that blocks with incorrect nonces are not accepted onto
%% the network.
add_bogus_block_nonce_test() ->
    ar_storage:clear(),
    ar_storage:write_tx(
        [
            TX1 = ar_tx:new(<<"HELLO WORLD">>),
            TX2 = ar_tx:new(<<"NEXT BLOCK.">>)
        ]
    ),
    Node = ar_node:start(),
    GS0 = ar_gossip:init([Node]),
    B0 = ar_weave:init([]),
    ar_storage:write_block(B0),
    B1 = ar_weave:add(B0, [TX1]),
    LastB = hd(B1),
    ar_storage:write_block(hd(B1)),
    BL = [hd(B1), hd(B0)],
    Node ! {replace_block_list, BL},
	B2 = ar_weave:add(B1, [TX2]),
    ar_storage:write_block(hd(B2)),
	ar_gossip:send(GS0,
		{new_block,
			self(),
			(hd(B2))#block.height,
			(hd(B2))#block { nonce = <<"INCORRECT">> },
			find_recall_block(B2)
		}
	),
	receive after 500 -> ok end,
	Node ! {get_blocks, self()},
	receive
        {blocks, Node, [RecvdB | _]} -> LastB = ar_storage:read_block(RecvdB)
    end.


%% @doc Ensure that blocks with bogus hash lists are not accepted by the network.
add_bogus_hash_list_test() ->
    ar_storage:clear(),
    ar_storage:write_tx(
        [
            TX1 = ar_tx:new(<<"HELLO WORLD">>),
            TX2 = ar_tx:new(<<"NEXT BLOCK.">>)
        ]
    ),
    Node = ar_node:start(),
    GS0 = ar_gossip:init([Node]),
    B0 = ar_weave:init([]),
    ar_storage:write_block(B0),
    B1 = ar_weave:add(B0, [TX1]),
    LastB = hd(B1),
    ar_storage:write_block(hd(B1)),
    BL = [hd(B1), hd(B0)],
    Node ! {replace_block_list, BL},
	B2 = ar_weave:add(B1, [TX2]),
    ar_storage:write_block(hd(B2)),
	ar_gossip:send(GS0,
		{new_block,
			self(),
			(hd(B2))#block.height,
			(hd(B2))#block {
				hash_list =
                    [<<"INCORRECT HASH">> | tl((hd(B2))#block.hash_list)]
			},
			find_recall_block(B2)
		}),
	receive after 500 -> ok end,
	Node ! {get_blocks, self()},
	receive
        {blocks, Node, [RecvdB | _]} -> LastB = ar_storage:read_block(RecvdB)
    end.

%% @doc Run a small, non-auto-mining blockweave. Mine blocks.
tiny_blockweave_with_mining_test() ->
	ar_storage:clear(),
	B0 = ar_weave:init([]),
	Node1 = start([], B0),
    ar_storage:write_block(B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	mine(Node1),
	receive after 1000 -> ok end,
	B1 = get_blocks(Node2),
	1 = (hd(ar_storage:read_block(B1)))#block.height.

%% @doc Ensure that the network add data and have it mined into blocks.
tiny_blockweave_with_added_data_test() ->
	ar_storage:clear(),
	TestData = ar_tx:new(<<"TEST DATA">>),
	ar_storage:write_tx(TestData),
	B0 = ar_weave:init([]),
    ar_storage:write_block(B0),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node2, TestData),
	receive after 1000 -> ok end,
	mine(Node1),
	receive after 1000 -> ok end,
	B1 = get_blocks(Node2),
	TestDataID  = TestData#tx.id,
	[TestDataID] = (hd(ar_storage:read_block(B1)))#block.txs.

%% @doc Test that a slightly larger network is able to receive data and
%% propogate data and blocks.
large_blockweave_with_data_test_slow() ->
	ar_storage:clear(),
	TestData = ar_tx:new(<<"TEST DATA">>),
	ar_storage:write_tx(TestData),
	B0 = ar_weave:init([]),
	Nodes = [ start([], B0) || _ <- lists:seq(1, 200) ],
	[ add_peers(Node, ar_util:pick_random(Nodes, 100)) || Node <- Nodes ],
	add_tx(ar_util:pick_random(Nodes), TestData),
	receive after 2500 -> ok end,
	mine(ar_util:pick_random(Nodes)),
	receive after 2500 -> ok end,
	B1 = get_blocks(ar_util:pick_random(Nodes)),
	TestDataID  = TestData#tx.id,
	[TestDataID] = (hd(ar_storage:read_block(B1)))#block.txs.

%% @doc Test that large networks (500 nodes) with only 1% connectivity
%% still function correctly.
large_weakly_connected_blockweave_with_data_test_slow() ->
	ar_storage:clear(),
	TestData = ar_tx:new(<<"TEST DATA">>),
	ar_storage:write_tx(TestData),
	B0 = ar_weave:init([]),
	Nodes = [ start([], B0) || _ <- lists:seq(1, 200) ],
	[ add_peers(Node, ar_util:pick_random(Nodes, 5)) || Node <- Nodes ],
	add_tx(ar_util:pick_random(Nodes), TestData),
	receive after 2500 -> ok end,
	mine(ar_util:pick_random(Nodes)),
	receive after 2500 -> ok end,
	B1 = get_blocks(ar_util:pick_random(Nodes)),
	TestDataID  = TestData#tx.id,
	[TestDataID] = (hd(ar_storage:read_block(B1)))#block.txs.

%% @doc Ensure that the network can add multiple peices of data and have
%% it mined into blocks.
medium_blockweave_mine_multiple_data_test_slow() ->
	{Priv1, Pub1} = ar_wallet:new(),
	{Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(9000), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = ar_tx:new(Pub3, ?AR(1), ?AR(500), <<>>),
	SignedTX2 = ar_tx:sign(TX2, Priv2, Pub2),
	B0 = ar_weave:init([]),
	Nodes = [ start([], B0) || _ <- lists:seq(1, 50) ],
	[ add_peers(Node, ar_util:pick_random(Nodes, 5)) || Node <- Nodes ],
	add_tx(ar_util:pick_random(Nodes), SignedTX),
	add_tx(ar_util:pick_random(Nodes), SignedTX2),
	receive after 1500 -> ok end,
	mine(ar_util:pick_random(Nodes)),
	receive after 1250 -> ok end,
	B1 = get_blocks(ar_util:pick_random(Nodes)),
	true =
        lists:member(
            SignedTX#tx.id,
            (hd(ar_storage:read_block(B1)))#block.txs
        ),
	true =
        lists:member(
            SignedTX2#tx.id,
            (hd(ar_storage:read_block(B1)))#block.txs
        ).

%% @doc Ensure that the network can mine multiple blocks correctly.
medium_blockweave_multi_mine_test() ->
	ar_storage:clear(),
	TestData1 = ar_tx:new(<<"TEST DATA1">>),
	ar_storage:write_tx(TestData1),
	TestData2 = ar_tx:new(<<"TEST DATA2">>),
	ar_storage:write_tx(TestData2),
	B0 = ar_weave:init([]),
	Nodes = [ start([], B0) || _ <- lists:seq(1, 50) ],
	[ add_peers(Node, ar_util:pick_random(Nodes, 5)) || Node <- Nodes ],
	add_tx(ar_util:pick_random(Nodes), TestData1),
	receive after 1000 -> ok end,
	mine(ar_util:pick_random(Nodes)),
	receive after 1000 -> ok end,
	B1 = get_blocks(ar_util:pick_random(Nodes)),
	add_tx(ar_util:pick_random(Nodes), TestData2),
	receive after 1000 -> ok end,
	mine(ar_util:pick_random(Nodes)),
	receive after 1000 -> ok end,
	B2 = get_blocks(ar_util:pick_random(Nodes)),
	TestDataID1 = TestData1#tx.id,
	TestDataID2 = TestData2#tx.id,
	[TestDataID1] = (hd(ar_storage:read_block(B1)))#block.txs,
	[TestDataID2] = (hd(ar_storage:read_block(B2)))#block.txs.

%% @doc Setup a network, mine a block, cause one node to forget that block.
%% Ensure that the 'truncated' node can still verify and accept new blocks.
tiny_collaborative_blockweave_mining_test() ->
	ar_storage:clear(),
	B0 = ar_weave:init([]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	mine(Node1), % Mine B2
	receive after 500 -> ok end,
	truncate(Node1),
	mine(Node2), % Mine B3
	receive after 500 -> ok end,
	B3 = get_blocks(Node1),
	3 = (hd(ar_storage:read_block(B3)))#block.height.


%% @doc Setup a network, mine a block, change the diff, then mine another.
change_difficulty_test() ->
	ar_storage:clear(),
	B0 = ar_weave:init([]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	B1 = get_current_block(Node1),
	mine_at_diff(Node1, NewDiff = (B1#block.diff + 1)),
	receive after 1000 -> ok end,
	B2 = get_current_block(Node1),
	2 = B2#block.height,
	NewDiff = B2#block.diff,
	mine(Node2), % Mine B1
	receive after 1000 -> ok end,
	B3 = get_current_block(Node1),
	NewDiff = B3#block.diff.

%% @doc Ensure that a 'claimed' block triggers a non-zero mining reward.
mining_reward_test() ->
	ar_storage:clear(),
	{_Priv1, Pub1} = ar_wallet:new(),
	Node1 = start([], ar_weave:init([]), 0, ar_wallet:to_address(Pub1)),
	mine(Node1),
	receive after 1000 -> ok end,
	true = (get_balance(Node1, Pub1) > 0).

%% @doc Check that other nodes accept a new block and associated mining reward.
multi_node_mining_reward_test() ->
	ar_storage:clear(),
	{_Priv1, Pub1} = ar_wallet:new(),
	Node1 = start([], B0 = ar_weave:init([])),
	Node2 = start([Node1], B0, 0, ar_wallet:to_address(Pub1)),
	mine(Node2),
	receive after 1000 -> ok end,
	true = (get_balance(Node1, Pub1) > 0).

%% @doc Create two new wallets and a blockweave with a wallet balance.
%% Create and verify execution of a signed exchange of value tx.
wallet_transaction_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	TX = ar_tx:new(ar_wallet:to_address(Pub2), ?AR(1), ?AR(9000), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	receive after 300 -> ok end,
	ar_storage:write_tx(SignedTX),
	mine(Node1), % Mine B1
	receive after 300 -> ok end,
	?AR(999) = get_balance(Node2, Pub1),
	?AR(9000) = get_balance(Node2, Pub2).

%% @doc Wallet0 -> Wallet1 | mine | Wallet1 -> Wallet2 | mine | check
wallet_two_transaction_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(9000), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = ar_tx:new(Pub3, ?AR(1), ?AR(500), <<>>),
	SignedTX2 = ar_tx:sign(TX2, Priv2, Pub2),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}], 8),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	ar_storage:write_tx([SignedTX]),
	receive after 300 -> ok end,
	mine(Node1), % Mine B1
	receive after 1000 -> ok end,
    add_tx(Node2, SignedTX2),
    ar_storage:write_tx([SignedTX2]),
	receive after 1000 -> ok end,
	mine(Node2), % Mine B2
    receive after 300 -> ok end,
	?AR(999) = get_balance(Node1, Pub1),
	?AR(8499) = get_balance(Node1, Pub2),
	?AR(500) = get_balance(Node1, Pub3).

%% @doc Wallet1 -> Wallet2 | Wallet1 -> Wallet3 | mine | check
%% @doc Wallet1 -> Wallet2 | Wallet1 -> Wallet3 | mine | check
single_wallet_double_tx_before_mine_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	OrphanedTX = ar_tx:new(Pub2, ?AR(1), ?AR(5000), <<>>),
	OrphanedTX2 = ar_tx:new(Pub3, ?AR(1), ?AR(4000), <<>>),
	TX = OrphanedTX#tx { owner = Pub1 },
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = OrphanedTX2#tx { owner = Pub1, last_tx = SignedTX#tx.id },
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	ar_storage:write_tx([SignedTX]),
	receive after 500 -> ok end,
	add_tx(Node1, SignedTX2),
	ar_storage:write_tx([SignedTX2]),
	receive after 500 -> ok end,
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	?AR(4999) = get_balance(Node2, Pub1),
	?AR(5000) = get_balance(Node2, Pub2),
	?AR(0) = get_balance(Node2, Pub3).

%% @doc Verify the behaviour of out of order TX submission.
%% NOTE: The current behaviour (out of order TXs get dropped)
%% is not necessarily the behaviour we want, but we should keep
%% track of it.
single_wallet_double_tx_wrong_order_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	{_Priv3, Pub3} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(5000), <<>>),
	TX2 = ar_tx:new(Pub3, ?AR(1), ?AR(4000), TX#tx.id),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX2),
	receive after 500 -> ok end,
	add_tx(Node1, SignedTX),
	ar_storage:write_tx([SignedTX]),
	receive after 500 -> ok end,
	mine(Node1), % Mine B1
	receive after 200 -> ok end,
	?AR(4999) = get_balance(Node2, Pub1),
	?AR(5000) = get_balance(Node2, Pub2),
    ?AR(0) = get_balance(Node2, Pub3),
    CurrentB = get_current_block(whereis(http_entrypoint_node)),
    length(CurrentB#block.txs) == 1.


%% @doc Ensure that TX Id threading functions correctly (in the positive case).
tx_threading_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(1000), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	TX2 = ar_tx:new(Pub2, ?AR(1), ?AR(1000), SignedTX#tx.id),
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	ar_storage:write_tx([SignedTX,SignedTX2]),
	receive after 500 -> ok end,
	mine(Node1), % Mine B1
	receive after 300 -> ok end,
	add_tx(Node1, SignedTX2),
	receive after 500 -> ok end,
	mine(Node1), % Mine B1
	receive after 1000 -> ok end,
	?AR(7998) = get_balance(Node2, Pub1),
	?AR(2000) = get_balance(Node2, Pub2).

%% @doc Ensure that TX Id threading functions correctly (in the negative case).
bogus_tx_thread_test_slow() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(1000), <<>>),
	TX2 = ar_tx:new(Pub2, ?AR(1), ?AR(1000), <<"INCORRECT TX ID">>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	SignedTX2 = ar_tx:sign(TX2, Priv1, Pub1),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	ar_storage:write_tx([SignedTX,SignedTX2]),
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	add_tx(Node1, SignedTX2),
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	?AR(8999) = get_balance(Node2, Pub1),
	?AR(1000) = get_balance(Node2, Pub2).

%% @doc Ensure that TX replay attack mitigation works.
replay_attack_test() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	TX = ar_tx:new(Pub2, ?AR(1), ?AR(1000), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	ar_storage:write_tx(SignedTX),
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	add_tx(Node1, SignedTX),
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	?AR(8999) = get_balance(Node2, Pub1),
	?AR(1000) = get_balance(Node2, Pub2).

%% @doc Ensure last_tx functions after block mine.
last_tx_test() ->
	ar_storage:clear(),
	{Priv1, Pub1} = ar_wallet:new(),
	{_Priv2, Pub2} = ar_wallet:new(),
	TX = ar_tx:new(ar_wallet:to_address(Pub2), ?AR(1), ?AR(9000), <<>>),
	SignedTX = ar_tx:sign(TX, Priv1, Pub1),
	ID = SignedTX#tx.id,
	B0 = ar_weave:init([{ar_wallet:to_address(Pub1), ?AR(10000), <<>>}]),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	add_peers(Node1, Node2),
	add_tx(Node1, SignedTX),
	ar_storage:write_tx(SignedTX),
	receive after 500 -> ok end,
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	ID = get_last_tx(Node2, Pub1).

%% @doc Ensure that rejoining functionality works
rejoin_test() ->
	ar_storage:clear(),
	B0 = ar_weave:init(),
	Node1 = start([], B0),
	Node2 = start([Node1], B0),
	mine(Node2), % Mine B1
	receive after 500 -> ok end,
	mine(Node1), % Mine B1
	receive after 500 -> ok end,
	rejoin(Node2, []),
	timer:sleep(500),
	get_blocks(Node1) == get_blocks(Node2).
