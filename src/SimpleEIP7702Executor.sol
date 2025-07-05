// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.23;

import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { ExecutionHelper } from "@erc7579/core/ExecutionHelper.sol";
import {
    CallType, ExecType, Execution, ModeCode
} from "./utils/Types.sol";
import { CALLTYPE_SINGLE, CALLTYPE_BATCH, EXECTYPE_DEFAULT, EXECTYPE_TRY } from "./utils/Constants.sol";

/**
 * @title SimpleEIP7702Executor
 * @notice Simplified EIP7702 contract with only self-execute functionality
 * @dev All executions are performed directly by the contract itself
 */
contract SimpleEIP7702Executor is ExecutionHelper {
    using ModeLib for ModeCode;
    using ExecutionLib for bytes;

    ////////////////////////////// State //////////////////////////////

    /// @custom:eip7702-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    ////////////////////////////// Errors //////////////////////////////

    /// @dev The call is from an unauthorized context.
    error UnauthorizedCallContext();

    /// @dev Error thrown when an execution with an unsupported CallType was made.
    error UnsupportedCallType(CallType callType);

    /// @dev Error thrown when an execution with an unsupported ExecType was made.
    error UnsupportedExecType(ExecType execType);

    ////////////////////////////// Modifiers //////////////////////////////

    /**
     * @dev Prevents direct calls to the implementation.
     * @dev Check that the execution is being performed through a delegatecall call (EIP7702).
     */
    modifier onlySelf() {
        if (address(this) == __self) revert UnauthorizedCallContext();
        _;
    }

    ////////////////////////////// External Methods //////////////////////////////

    /**
     * @notice Executes an Execution from this contract
     * @param _execution The Execution to be executed
     */
    function execute(Execution calldata _execution) external payable onlySelf {
        _execute(_execution.target, _execution.value, _execution.callData);
    }

    /**
     * @notice Executes an Execution from this contract with mode support
     * @param _mode The ModeCode for the execution
     * @param _executionCalldata The calldata for the execution
     */
    function execute(ModeCode _mode, bytes calldata _executionCalldata) external payable onlySelf {
        (CallType callType_, ExecType execType_,,) = _mode.decode();

        // Check if calltype is batch or single
        if (callType_ == CALLTYPE_BATCH) {
            // destructure executionCallData according to batched exec
            Execution[] calldata executions_ = _executionCalldata.decodeBatch();
            // Check if execType is revert or try
            if (execType_ == EXECTYPE_DEFAULT) _execute(executions_);
            else if (execType_ == EXECTYPE_TRY) _tryExecute(executions_);
            else revert UnsupportedExecType(execType_);
        } else if (callType_ == CALLTYPE_SINGLE) {
            // Destructure executionCallData according to single exec
            (address target_, uint256 value_, bytes calldata callData_) = _executionCalldata.decodeSingle();
            // Check if execType is revert or try
            if (execType_ == EXECTYPE_DEFAULT) {
                _execute(target_, value_, callData_);
            } else if (execType_ == EXECTYPE_TRY) {
                bytes[] memory returnData_ = new bytes[](1);
                bool success_;
                (success_, returnData_[0]) = _tryExecute(target_, value_, callData_);
                if (!success_) emit TryExecuteUnsuccessful(0, returnData_[0]);
            } else {
                revert UnsupportedExecType(execType_);
            }
        } else {
            revert UnsupportedCallType(callType_);
        }
    }

    /**
     * @notice Allows this contract to receive native tokens
     */
    receive() external payable {}
} 