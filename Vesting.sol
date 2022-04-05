// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SampleTokenVesting is Ownable{
    using SafeMath for uint256;
    struct VestingSchedule{
        bool initialized;
        address  beneficiary;
        uint256  cliff;
        uint256  start;
        uint256  duration;
        uint256 slicePeriodSeconds;
        bool  revocable;
        uint256 amountTotal;
        uint256  released;
        bool revoked;
    }

    IERC20 immutable private _token;
    bytes32[] private vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;
    mapping(address => uint256) private shedulesPerBenficiary;

    event Released(uint256 amount);
    event Revoked();

    
    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId) {
        require(vestingSchedules[vestingScheduleId].initialized == true);
        _;
    }
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(vestingSchedules[vestingScheduleId].initialized == true);
        require(vestingSchedules[vestingScheduleId].revoked == false);
        _;
    }
   
    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    receive() external payable {}

    fallback() external payable {}

    
    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revocable,
        uint256 _amount
    )
        public
        onlyOwner{
        require(
            this.getWithdrawableAmount() >= _amount,
            "cannot create vesting schedule because not sufficient tokens"
        );
        require(_duration > 0, "duration must be > 0");
        require(_amount > 0, "amount must be > 0");
        require(_slicePeriodSeconds >= 1, "slicePeriodSeconds must be >= 1");
        //compute sheduleId
        bytes32 vestingScheduleId = computeScheduleId(_beneficiary);
        uint256 cliff = _start.add(_cliff);
        //vestingShedules map key = computed sheduleId
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            _beneficiary,
            cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _revocable,
            _amount,
            0,
            false
        );
        //update total amount held inside the vesting shedules
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        vestingSchedulesIds.push(vestingScheduleId);
        //check current shedules count of beneficiary
        uint256 currentVestingCount = shedulesPerBenficiary[_beneficiary];
        //update count
        shedulesPerBenficiary[_beneficiary] = currentVestingCount.add(1);
    }
   
    function computeScheduleId(address holder)
        private
        view
        returns(bytes32){
            return keccak256(abi.encodePacked(holder, shedulesPerBenficiary[holder]));
    }

    
    function release(
        bytes32 vestingScheduleId,
        uint256 amount
    )
        public
        onlyIfVestingScheduleNotRevoked(vestingScheduleId){
        //get vesting shedule struct from map using sheduleId
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        //checks caller is beneficiary or owner
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(
            isBeneficiary || isOwner,
            "only beneficiary and owner can release vested tokens"
        );
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released.add(amount);
        //get the beneficiary from struct
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(amount);
        _token.transfer(beneficiaryPayable, amount);
    }
function revoke(bytes32 vestingScheduleId)
        public
        onlyOwner
        onlyIfVestingScheduleNotRevoked(vestingScheduleId){
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.revocable == true, " vesting is not revocable");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if(vestedAmount > 0){
            release(vestingScheduleId, vestedAmount);
        }
        uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(unreleased);
        vestingSchedule.revoked = true;
    }
  
   //transfer unused amount to owner
    function withdraw(uint256 amount)
        public
        onlyOwner{
        require(this.getWithdrawableAmount() >= amount, "not enough withdrawable funds");
        _token.transfer(owner(), amount);
    }

    function getWithdrawableAmount()
        public
        view
        returns(uint256){
        return _token.balanceOf(address(this)).sub(vestingSchedulesTotalAmount);
    }
    
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(uint256){
        if ((block.timestamp < vestingSchedule.cliff) || vestingSchedule.revoked == true) {
            return 0;
            //if completed vesting duration
        } else if (block.timestamp >= vestingSchedule.start.add(vestingSchedule.duration)) {
            //result=vertsing shedule total amount - already released amount if any
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            uint256 timeFromStart = block.timestamp.sub(vestingSchedule.start);
            uint secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicePeriods.mul(secondsPerSlice);
            //vested amount = (vertsing shedule total amount * total vested seconds)/duration 
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            vestedAmount = vestedAmount.sub(vestingSchedule.released);
            return vestedAmount;
        }
    }
//compute releasable amount for a shedule id
    function computeReleasableAmount(bytes32 vestingScheduleId)
        public
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
        view
        returns(uint256){
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }
  
    function getVestingIdAtIndex(uint256 index)
    external
    view
    returns(bytes32){
        require(index < getVestingSchedulesCount(), "index out of bounds");
        return vestingSchedulesIds[index];
    }
     function getVestingSchedule(bytes32 vestingScheduleId)
        public
        view
        returns(VestingSchedule memory){
        return vestingSchedules[vestingScheduleId];
    }

    function getVestingSchedulesCount()
        public
        view
        returns(uint256){
        return vestingSchedulesIds.length;
    }
   
    function getToken()
    external
    view
    returns(address){
        return address(_token);
    }

 function getVestingSchedulesCountByBeneficiary(address _beneficiary)
    external
    view
    returns(uint256){
        return shedulesPerBenficiary[_beneficiary];
    }
   
   
}
