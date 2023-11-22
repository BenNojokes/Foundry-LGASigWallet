// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract LGASigWallet {
/* Errors */
    error LGASigWallet__NoOwnersOnWallet();
    error LGASigWallet__NotAnOwnerOfWallet();
    error LGASigWallet__SenderNotAuthorized();
    error LGASigWallet__TxDoesNotExist();
    error LGASigWallet__TxAlreadyExecuted();
    error LGASigWallet__TxAlreadyApproved();
    error LGASigWallet__TxExecutionFailed();
    error LGASigWallet__TxNotApproved();
    error LGASigWallet__InvalidOwner();
    error LGASigWallet__OwnerAlreadyExists();
    error LGASigWallet__NotEnoughApprovals();
    error LGASigWallet__CannotRemoveSelf();
    error LGASigWallet__RemovingOwnerViolatesQuorum();

/* Type declarations */
    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
        uint quorum;
    }
    
/* State variables */
    address[] public owners;
    uint public quorum;
    mapping(address => bool) public isOwner;
    mapping(uint => mapping(address => bool))  public txApproved;
    Transaction[] public transactions;
    
/* Events */
    event Deposit(
        address indexed sender, 
        uint amount, 
        uint balance
    );
    event SubmitTransaction(
        address indexed owner,
        uint indexed txId,
        address indexed to,
        uint value,
        bytes data
    );
    event ApproveTransaction(address indexed owner, uint indexed txId);
    event RevokeApproval(address indexed owner, uint indexed txId);
    event ExecuteTransaction(address indexed owner, uint indexed txId);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed removedOwner);

/* Modifiers */
    modifier onlyOwner() {
        if(!isOwner[msg.sender]) {
        revert LGASigWallet__SenderNotAuthorized();
        }
        _;
    }

    modifier txExists(uint _txId) {
        if(_txId > transactions.length) {
            revert LGASigWallet__TxDoesNotExist();
        }
        _;
    }

    modifier notApproved(uint _txId) {
        if(txApproved[_txId][msg.sender]) {
            revert LGASigWallet__TxAlreadyApproved();
        }
        _;
    }

    modifier notExecuted(uint _txId) {
        if(transactions[_txId].executed) {
            revert LGASigWallet__TxAlreadyExecuted();
        }
        _;
    }

/* Functions */
    constructor(address [] memory _owners) {
        if(_owners.length == 0) {
            revert LGASigWallet__NoOwnersOnWallet();
        }

        for(uint i; i < _owners.length; i++) {
            address owner = _owners[i];
            if(owner == address(0)) {
                revert LGASigWallet__InvalidOwner();
            }
            if(isOwner[owner]) {
                revert LGASigWallet__OwnerAlreadyExists();
            }

            isOwner[owner] = true;
            owners.push(owner);
        }
        // Sets the quorum to 80% approve of owners for Tx execution
        quorum = (owners.length * 8) / 10;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function submitTransaction(
        address _to, 
        uint _value, 
        bytes memory _data
    ) public onlyOwner {
        uint txId = transactions.length;
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                quorum: 0
            })
        );
        emit SubmitTransaction(msg.sender, txId, _to, _value, _data);
    }

    function approveTransaction(uint _txId)
        public 
        onlyOwner 
        txExists(_txId) 
        notApproved(_txId) 
        notExecuted(_txId) 
    {
        Transaction storage transaction = transactions[_txId];
        transaction.quorum += 1;
        txApproved[_txId][msg.sender] = true;

        emit ApproveTransaction(msg.sender, _txId);
    }

    function executeTransaction(uint _txId) 
        public
        onlyOwner 
        txExists(_txId) 
        notExecuted(_txId) 
        {
            Transaction storage transaction = transactions[_txId];
            if(transaction.quorum <= quorum) {
                revert LGASigWallet__NotEnoughApprovals();
            }

        transaction.executed = true;

        (bool success, ) = transaction.to.call{
            value: transaction.value
        }(
            transaction.data
        );
        if(!success) {
            revert LGASigWallet__TxExecutionFailed();
        }
        emit ExecuteTransaction(msg.sender, _txId);
    }

    function revokeApproval(uint _txId) 
        public
        onlyOwner 
        txExists(_txId) 
        notExecuted (_txId)
    {
        Transaction storage transaction = transactions[_txId];

        if(!txApproved[_txId][msg.sender]) {
            revert LGASigWallet__TxNotApproved();
        }

        transaction.quorum -= 1;
        txApproved[_txId][msg.sender] = false;
        
        emit RevokeApproval(msg.sender, _txId);
    }

    function addOwner(address newOwner) external onlyOwner {
        if(newOwner == address(0)) {
            revert LGASigWallet__InvalidOwner();
        }
        if(isOwner[newOwner]) {
            revert LGASigWallet__OwnerAlreadyExists();
        }

        owners.push(newOwner);
        isOwner[newOwner] = true;

        quorum = (owners.length * 8) / 10;

        emit OwnerAdded(newOwner);
    }

    function removeOwner(address removeThisOwner) external onlyOwner {
        if (!isOwner[removeThisOwner]) {
            revert LGASigWallet__NotAnOwnerOfWallet();
        }
        if (removeThisOwner == msg.sender) {
            revert LGASigWallet__CannotRemoveSelf();
        }
        if (owners.length - 1 <= quorum) {
            revert LGASigWallet__RemovingOwnerViolatesQuorum();
        }
        isOwner[removeThisOwner] = false;
    // Remove requested owner from the array
        uint256 ownerToRemove;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == removeThisOwner) {
                ownerToRemove = i;
                break;
            }
        }
        if(ownerToRemove >= owners.length) {
            revert LGASigWallet__InvalidOwner();
        }
    // Swap with the previous index
        owners[ownerToRemove] = owners[owners.length - 1];
    // Remove the last index
        owners.pop();
        quorum = (owners.length * 8) / 10;
        emit OwnerRemoved(removeThisOwner);
    }

/* Getter Functions */
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint) {
        return transactions.length;
    }

    function getTransaction(uint _txId)
        public
        view
        returns (
            address to,
            uint value,
            bytes memory data,
            bool executed,
            uint quorumNum
        )
    {
        Transaction storage transaction = transactions[_txId];

        return(
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.quorum
        );
    }
}