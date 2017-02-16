pragma solidity ^0.4.8;

contract VirtualPaymentMachine {
    
    // datatype for state channel id
    struct VpmId {
        address Alice;
        address Inter;
        address Bob;
        uint sid;
    }

    // datatype for virtual state
    struct VpmState {
        uint AliceCash;
        uint BobCash;
        uint seqNo;
        uint validity;
        uint extendedValidity;
        bool open;
        bool waitingForAlice;
        bool waitingForBob;
        bool init;
    }

    // datatype for virtual state
    mapping (bytes32 => VpmState) public states;
    VpmState public s;
    bytes32 public id;


    function getDistribution(address alice, address inter, address bob, uint sid) returns (bool, uint, uint) {
        id = sha3(alice, inter, bob, sid);
        if (states[id].init) {
            if (states[id].extendedValidity < now)
                states[id].open = false;
            if (states[id].open)
                return (false, 0, 0);
            else
                return (true, states[id].AliceCash, states[id].BobCash);
        }
        else
            return (false, 0, 0);
    }

    function exec(address alice, address inter, address bob, uint sid, uint version, uint aliceCash, uint bobCash,
            bytes signA, bytes signB) {

        // verfiy signatures
        bytes32 msgHash = sha3(id, version, aliceCash, bobCash);
        if (!verify(alice, msgHash, signA)) return;
        if (!verify(bob, msgHash, signB)) return;

        id = sha3(alice, inter, bob, sid);
        s = states[id];
        // if such a virtual channel state does not exist yet, create one
        if (!s.init) {
            uint validity = now + 10 minutes;
            uint extendedValidity = validity + 10 minutes;
            s = VpmState(aliceCash, bobCash, version, validity, extendedValidity, true, true, true, true);
        }

        // if channel is closed or timeouted do nothing
        if (!s.open || s.extendedValidity < now) return;
        if ((s.validity < now) && (msg.sender == alice || msg.sender == bob)) return;
 
        // check if the message is from alice or bob
        if (msg.sender == alice) s.waitingForAlice = false;
        if (msg.sender == bob) s.waitingForBob = false;

        // set values of Internal State
        if (version > s.seqNo) {
            s = VpmState(aliceCash, bobCash, version, s.validity, s.extendedValidity, true, s.waitingForAlice, s.waitingForBob, true);
        }

        // execute if both players responded
        if (!s.waitingForAlice && !s.waitingForBob) {
            s.open = false;
        }
        states[id] = s;
    }

    function verify(address addr, bytes32 m, bytes sig) returns(bool) {
        if (sig.length != 65)
            return (false);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27)
            v += 27;

        if (v != 27 && v != 28)
            return (false);

        address pk = ecrecover(m, v, r, s);

        if (pk == addr)
            return (true);
        else return (false);
    }
}

////////////////////////////////////////////////////////////////// BASIC //////////////////////////////////////////////////////////////////////

contract BasicChannelContract {
    //Data type for Internal Contract
    struct Party {
        address id;
        uint cash;
        bool waitForInput;
    }

    //Data type for Internal Contract
    struct InternalContract {
        bool active;
        VirtualPaymentMachine vpm;
        uint sid;
        uint blockedA;
        uint blockedB;
        uint version;
    }

    // State options
    enum ChannelStatus {Init, Open, InConflict, Settled, WaitingToClose, ReadyToClose}

    // Basic Channel variables
    Party public alice;
    Party public bob;
    uint public timeout;
    InternalContract public c;
    ChannelStatus public status;

    /*
    * Constructor for setting intial variables takes as input
    * of the parties of the basic channel
    */
    function BasicChannelContract(address _addressAlice, address _addressBob) {
        // set addresses
        alice.id = _addressAlice;
        bob.id = _addressBob;

        // set limit until which Alice and Bob need to respond
        timeout = now + 100 minutes;
        alice.waitForInput = true;
        bob.waitForInput = true;

        // set other initial values
        status = ChannelStatus.Init;
        c.active = false;
    }

    /*
    * This functionality is used to send funds to the contract during 100 minutes after channel creation
    */
    function CreateBasicChannel() payable {
        if (status != ChannelStatus.Init) throw;

        // in case one of the players did not respond in time:
        if (now > timeout) {
            // refund money
            if (alice.waitForInput && alice.cash > 0) {
                if (!alice.id.send(alice.cash)) throw;
            }
            if (bob.waitForInput && bob.cash > 0) {
                if (!bob.id.send(bob.cash)) throw;
            }

            // terminate contract
            selfdestruct(alice.id);
            return;
        }

        // Response (in time) from Player A
        if (alice.waitForInput && msg.sender == alice.id) {
            alice.cash = msg.value;
            alice.waitForInput = false;
        }

        // Response (in time) from Player B
        if (bob.waitForInput && msg.sender == bob.id) {
            bob.cash = msg.value;
            bob.waitForInput = false;
        }

        // execute if both players responded
        if (!alice.waitForInput && !bob.waitForInput) {
            status = ChannelStatus.Open;
            timeout = 0;
        }
    }

    /*
    * This functionality verifys ECDSA signatures
    * @param     public key p,
    *            message m,
    *            signature parameter v, r, s
    * @returns   true if the signature of p over m was correct
    */
    function verify(address addr, bytes32 m, bytes sig) returns(bool) {
        if (sig.length != 65)
            return (false);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27)
            v += 27;

        if (v != 27 && v != 28)
            return (false);

        address pk = ecrecover(m, v, r, s);

        if (pk == addr)
            return (true);
        else return (false);
    }

    /*
    * This functionality is called whenever the channel state needs to be established
    * it is called by both, alice and bob
    * @param     contract address: vpm, _sid,
                 blocked funds from A and B: blockedA and blockedB,
                 version parameter: version,
    *            signature parameter (from A and B): v, r, s
    */
    function establishBasicChannelState
            (address _vpm, uint _sid, uint _blockedA, uint _blockedB, uint _version, bytes sigA, bytes sigB) {
        // check if the parties have enough funds in the contract
        if (alice.cash < _blockedA || bob.cash < _blockedB) return;

        // verfify correctness of the signatures
        bytes32 msgHash = sha3(_vpm, _sid, _blockedA, _blockedB, _version);
        if (!verify(alice.id, msgHash, sigA)) return;
        if (!verify(bob.id, msgHash, sigB)) return;

        // execute on first call
        if (status == ChannelStatus.Open || status == ChannelStatus.WaitingToClose) {
            status = ChannelStatus.InConflict;
            alice.waitForInput = true;
            bob.waitForInput = true;
            timeout = now + 100 minutes;
        }
        if (status != ChannelStatus.InConflict) return;

        // record if message is sent by alice and bob
        if (msg.sender == alice.id) alice.waitForInput = false;
        if (msg.sender == bob.id) bob.waitForInput = false;

        // set values of InternalContract
        if (_version > c.version) {
            c.active = true;
            c.vpm = VirtualPaymentMachine(_vpm);
            c.sid = _sid;
            c.blockedA = _blockedA;
            c.blockedB = _blockedB;
            c.version = _version;
        }

        // execute if both players responded or timeout passed
        if ((!alice.waitForInput && !bob.waitForInput) || now > timeout) {
            status = ChannelStatus.Settled;
            alice.waitForInput = false;
            bob.waitForInput = false;
            alice.cash -= c.blockedA;
            bob.cash -= c.blockedB;
        }
    }

    /*
    * This functionality éxecutes the internal VPM Machine when the state is settled
    * @param     redistributed funds from A and B: cashA and cashB,
                 version parameter: version,
    *            signature parameter (from A and B): v, r, s
    */
    function executeMachine(address _alice, address _inter, address _bob) {
        if (status != ChannelStatus.Settled) return;

        // call virtual payment machine on the params
        var (s, a, b) = c.vpm.getDistribution(_alice, _inter, _bob, c.sid);

        // check if the result makes sense
        if (a + b != c.blockedA + c.blockedB || !s) return;

        // Otherwise, adapt parameters
        alice.cash += a;
        c.blockedA -= a;
        bob.cash += b;
        c.blockedB -= b;

        // send funds to A and B
        if (alice.id.send(alice.cash)) alice.cash = 0;
        if (bob.id.send(bob.cash)) bob.cash = 0;

        // terminate channel
        if (alice.cash == 0 && bob.cash == 0) selfdestruct(alice.id);
    }

    /*
    * This functionality closes the channel when there is no (more) internal machine
    */
    function closeChannel() {
        // check if function is allowed
        if (status == ChannelStatus.Open) {
            status = ChannelStatus.WaitingToClose;
            alice.waitForInput = true;
            bob.waitForInput = true;
        }

        if (status != ChannelStatus.WaitingToClose) return;

        // Response (in time) from Player A
        if (alice.waitForInput && msg.sender == alice.id)
            alice.waitForInput = false;

        // Response (in time) from Player B
        if (bob.waitForInput && msg.sender == bob.id)
            bob.waitForInput = false;

        if (!alice.waitForInput && !bob.waitForInput) {
            // send funds to A and B
            if (alice.id.send(alice.cash)) alice.cash = 0;
            if (bob.id.send(bob.cash)) bob.cash = 0;

            // terminate channel
            if (alice.cash == 0 && bob.cash == 0) selfdestruct(alice.id);
        }
    }
}

