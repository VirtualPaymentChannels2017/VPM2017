pragma solidity ^0.4.0;

library LibSignatures {
    event EventVerificationSucceeded(bytes Signature, bytes32 Message, address Key);
    event EventVerificationFailed(bytes Signature, bytes32 Message, address Key);

    /*
    * This functionality verifies ECDSA signatures
    * @returns true if the _signature of _address over _message is correct
    */
    function verify(address _address, bytes32 _message, bytes _signature) constant returns(bool) {
        if (_signature.length != 65)
            return (false);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        if (v < 27)
            v += 27;

        if (v != 27 && v != 28)
            return (false);

        address pk = ecrecover(_message, v, r, s);

        if (pk == _address) {
            EventVerificationSucceeded(_signature, _message, pk);
            return (true);
        } else {
            EventVerificationFailed(_signature, _message, pk);
            return (false);
        }
    }
}
