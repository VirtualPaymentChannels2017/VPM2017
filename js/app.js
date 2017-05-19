if (typeof web3 !== 'undefined') {
    web3 = new Web3(web3.currentProvider);
} else {
    //set the provider you want from Web3.providers
    //web3 = new Web3(new Web3.providers.HttpProvider('http://dev.lisaeckey.de:31415'));
    var Web3 = require('web3');
    var web3 = new Web3();
    web3.setProvider(new web3.providers.HttpProvider("http://localhost:8545"));
}
if (web3.isConnected()){
    $('#login-modal').show();
}
else{
    $('#login-modal').hide();
    $('#CORS-modal').removeClass('hidden');
}
var accounts = web3.eth.accounts;
var htmlContent = '';
$.each(accounts, function (i, p) {
    htmlContent += '<option>' + p + '</option>';
});
$('#available_accounts').html(htmlContent);

var account;
var name;
var balance;

$('#welcome').hide();
$('#page-content').hide();

var basicContracts = []; // array
var basicContract;      // object {address:"0x...", associate:"0x...", name:"Bob", xa="5", xb="5",
                        // timeout:"01.01.2017:17:28", version "5", sig:"0x...", blocked: "1324", virtualSet:"[...]"};
var virtualContract;    // object {address:"0x...", associate:"0x...", name:"Bob", xa="5", xb="5",
                        // timeout:"01.01.2017:17:28", version "5", sig:"0x..."};

var basicChannelAbi;
var basicChannelCode;
$.getJSON("build/contracts/StateContract.json", function (json) {
    basicChannelAbi = json.abi;
    basicChannelCode = json.unlinked_binary;
});

var virtualChannelAbi;
var virtualChannelCode;
$.getJSON("build/contracts/VPC.json", function (json) {
    virtualChannelAbi = json.abi;
    virtualChannelCode = json.unlinked_binary;
});

var deploymentCheck;
var deploymentCheckRuns;
var update;
var updateRuns;


$(function () {
    $('#login-submit').click(function () {
        account = $('#available_accounts').val();
        var weiBalance = web3.eth.getBalance(account);
        console.log(weiBalance);
        balance = web3.fromWei(weiBalance.toString(),'ether');
        $('#name').html($('#login-name').val());
        $('#address').html(account.toString());
        $('#balance').html(balance);
        show('#welcome');
        show('#page-content');
        $('#login-modal').hide();
        setStatus("Connection to Blockchain established", 1);
    });

    $('#new-channel').click(function () {
        show('#create-basic-channel-screen');
    });

    $('#input-address-toogle').click(function () {
        $('#input-address-form').toggle();
    });

    $('#create-submit').click(function () {
        var contract;
        var address = $('#input-address').val();
        if (address == "") {
            contract = web3.eth.contract(basicChannelAbi).new({data: basicChannelCode, from: account, gas: 3000000});
            deployContract(contract);
        } else {
            contract = web3.eth.contract(basicChannelAbi).at(address);
            connectToContract(contract);
        }
    });


    setStatus = function (message, impact) {
        var status = $('#status').html(message);
        if (impact == 0) status.hide();
        else status.show();
        if (impact == 1) status.attr('class', 'alert alert-success fade in');
        if (impact == 2) status.attr('class', 'alert-warning fade in');
        if (impact == 3) status.attr('class', 'alert alert-danger fade in');
    };

    show = function (e) {
        var element = $(e);
        element.removeClass('hidden');
        element.show();
    };


    deployContract = function(contract){

        deploymentCheckRuns = 0;
        var otherAccount = $('#basic-user-address').val();
        deploymentCheck = setInterval(function() {
            deploymentCheckRuns++;
            if (deploymentCheckRuns > 10) {
                clearInterval(deploymentCheck);
            }
            if (typeof contract.address !== "undefined") {
                console.log("Your contract is being deployed with address " +contract.address);

                clearInterval(deploymentCheck);

                contract.Init(account, otherAccount, {from: account, gas: 300000}, function(error, result){
                    if(!error) {
                        fundChannel(contract, account, otherAccount, "Your", $('#basic-user-name').val() + "s", $('#basic-deposit').val());
                    } else console.error(error);
                });
            }
        }, 1000);
    };

    connectToContract = function(contract){

        var name = $('#basic-user-name').val();
        var amount = $('#basic-deposit').val();
        deploymentCheckRuns = 0;
        deploymentCheck = setInterval(function() {
            deploymentCheckRuns++;
            if (deploymentCheckRuns > 10) {
                clearInterval(deploymentCheck);
            }
            if (typeof contract.address !== "undefined") {
                console.log("You connected you contract with address " +contract.address);
                clearInterval(deploymentCheck);

                console.log(contract.bob.call()[2],contract.status.call().e);
                if (contract.bob.call()[2] && contract.status.call().e == 0)
                    fundChannel(contract, contract.alice.id, account, name+"s", "Your", amount);
                else{
                    updateChannelSelect(contract);
                    addChannelToList(contract, contract.alice.id, account, name+"s", "Your");
                }
            }
        }, 1000);
    };

    fundChannel = function(contract, leftAccount, rightAccount, nameL, nameR, amount) {

        addChannelToList(contract, leftAccount, rightAccount, nameL, nameR);
        updateChannelList();
        $('#create-channel-modal').hide();
        console.log(contract);
        contract.confirm({from: account, value: web3.toWei(amount, "ether")}, function(error, result){
            if(!error){
                updateChannelSelect(contract);
            } else console.error(error);
        });
    };

    addChannelToList = function (contract, leftAccount, rightAccount, nameL, nameR) {
        basicContract = {
            contract: contract,
            address: contract.address,
            leftName: nameL,
            rightName: nameR,
            version: contract.c.version,
            sigLeft: "0",
            sigRight: "0",
            virtualSet: [],
            notification: "1"
        };
        basicContracts.push(basicContract);
        var i = basicContracts.length-1;
        var li = $("<li href='#'>");
        li.click(function(){
            updateChannelSelect(contract)
        });
        li.addClass("list-group-item");
        li.attr("id","li_"+contract.address);
        $('#channel-list').append(li);
        // updateRuns = 0;
        // update = setInterval(function() {
        //     updateRuns++;
        //     updateChannelList();
        // }, 3000);
    };

    updateChannelList = function () {

        var badge;
        $.each(basicContracts, function (i, c) {

            contract = web3.eth.contract(basicChannelAbi).at(c.address);
            // console.log(i,contract);
            if (c.notification == 0) badge = "";
            else {
                badge = "<span class='badge'>"+c.notification+"</span>";
                c.notification = 0;
            }
            var n;
            if (c.leftName == "Your"){
                n = c.rightName
            } else n = c.leftName;
            var li = $('#li_'+c.address);
            var tmp = contract.bob.call()[1].toNumber()+contract.alice.call()[1].toNumber();
            tmp = web3.fromWei(tmp,"ether");
            li.html(n+' channel (with ' + tmp + ' Ether)' + badge);
        });
    };

    updateChannelSelect = function(contract){

        var contractAddress = contract.address;
        $("li").removeClass("active");
        var li = $('#li_'+contractAddress);
        li.addClass("active");
        var contractTmp, index;
        $.each(basicContracts, function (i, c) {
            if (contractAddress == c.address){
                index = i;
                contractTmp = c;
            }
        });
        $('#channel-address').html(contractAddress);
        $('#name-left').html(contractTmp.leftName);
        $('#channel-cash-left').html(web3.fromWei(contract.alice.call()[1].toString(),"ether"));
        $('#name-right').html(contractTmp.rightName);
        $('#channel-cash-right').html(web3.fromWei(contract.bob.call()[1].toString(),"ether"));
        console.log(contract);
        $('#channel-cash-blocked').html(web3.fromWei(contract.c.call()[3].toNumber()+contract.c.call()[4].toNumber()),"ether");
        if (typeof contractTmp.virtualSet !== "undefined") {
            $('#channel-virtual-address').html('<button type="button" class="btn" data-toggle="modal" data-target="#add-virtual-channel-modal">Create new virtual Channel</button>');
        } else {
            $('#channel-virtual-address').html(contractTmp.virtualSet[0]);
        }
        show('#channel-select');
    };


    $('#create-virtual-submit').click(function () {
        var contract = web3.eth.contract(virtualChannelAbi).new({data: virtualChannelCode, from: account, gas: 3000000}, function(error, result){
            if(!error) {
                $('#channel-virtual-address').html(contract.address);
                var otherName = $('#virtual-user-name').val();
                $('#name-virutal').html(otherName);
                show('#virtual-channel-select');
                updateVirtualChannelSelect(contract, "Your", otherName);
            } else console.error(error);
        })
    });

    updateVirtualChannelSelect = function(contract, leftname, rightname){
        $('#virtual-name-left').html(leftname);
        console.log(contract);
        $('#virtual-channel-cash-left').html(web3.fromWei(contract.s.call()[1].toString(),"ether"));
        $('#virtual-name-right').html(rightname);
        $('#virtual-channel-cash-right').html(web3.fromWei(contract.s.call()[1].toString(),"ether"));
        console.log(contract);
        $('#channel-cash-blocked').html(web3.fromWei(contract.c.call()[3].toNumber()+contract.c.call()[4].toNumber()),"ether");
        if (typeof contractTmp.virtualSet !== "undefined") {
            $('#channel-virtual-address').html('<button type="button" class="btn" data-toggle="modal" data-target="#add-virtual-channel-modal">Create new virtual Channel</button>');
        } else {
            $('#channel-virtual-address').html(contractTmp.virtualSet[0]);
        }
        show('#channel-select');
    };
});

