// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    // Scalar field size
    uint256 constant r    = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q   = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax  = 20271393493469871173572132209102235822982362344335722917727196559160584308264;
    uint256 constant alphay  = 7843795352160579649982960800198346689749733218678657422446249153045011438887;
    uint256 constant betax1  = 17840433407326282383080362070838916904574410183632472563591939737525751556503;
    uint256 constant betax2  = 12727801971106844995116359760428578636541892383336835174020017670880724773267;
    uint256 constant betay1  = 17586447429969529590097385423913201896312416663347977254034365190474901541377;
    uint256 constant betay2  = 10681962561559100751857179817449241692525090936182322379420055834290756429686;
    uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 = 5310390462364561152266987589802535939083639903693435819120471178364479229761;
    uint256 constant deltax2 = 9272380606608435931121141093856056252341148341587877949271948436156940227861;
    uint256 constant deltay1 = 10703450559617834523683062935736721425866837512124538947838919461017891550775;
    uint256 constant deltay2 = 19460706225911532668365225031677794615532737562495210585677024637979010919612;

    
    uint256 constant IC0x = 11502097316494119024171907464164445236869054375827921179516149473566302286943;
    uint256 constant IC0y = 18483171166701438288995111682449945432902420593815412167016050462223705802122;
    
    uint256 constant IC1x = 16674730189314261798212236314218732573173619484949671438826697842004712535940;
    uint256 constant IC1y = 6938733387541600790628472597871414248686723036779033057848876907600081397473;
    
    uint256 constant IC2x = 20248332545772315090444447315863451627263428398034099700230662825782498033140;
    uint256 constant IC2y = 20893343824158059641381968805840530060041455497014600425696493370283799864127;
    
    uint256 constant IC3x = 11132422754626796728081453258442671677856593273371967295965799964030982831197;
    uint256 constant IC3y = 1290919195998514097464501902351798645708429918811767447490468571497269310558;
    
    uint256 constant IC4x = 7453250270111635555063721892892223553555377153322908352218949502214096680562;
    uint256 constant IC4y = 4614113064914052515462962555591130776647325951619819117423622368079922902156;
    
    uint256 constant IC5x = 11134289620227231898333701866729114157222365714123884508117768744449107017368;
    uint256 constant IC5y = 422626994032702843562927576023971918029144065699302331585574384526322914106;
    
    uint256 constant IC6x = 5224428096313092501988875582318208805085231842239556322490928935123083979498;
    uint256 constant IC6y = 4292746320577930762132083254162051559626444601812567471009251831105007121948;
    
    uint256 constant IC7x = 12020941809634863681198644018415051481879398629747154145053808400048666138854;
    uint256 constant IC7y = 15245105508740783866748856109643183754148058164558366779799151598742104539609;
    
    uint256 constant IC8x = 5599604262976537009850101279601533944182781912811271382532253776526873695735;
    uint256 constant IC8y = 2020380385486594032875632426373547729981085389378152988297236109447397812756;
    
    uint256 constant IC9x = 8074303724138042347048352909805010185829456307598016100947571369329987892580;
    uint256 constant IC9y = 21433285668607921514581938974626636890993134213263479470304288327059479176211;
    
    uint256 constant IC10x = 14873820385080415869286361691894181160459198751247894972234638975736288134076;
    uint256 constant IC10y = 12037202548130299831412528304037844353249236048433029895107327950442834447654;
    
 
    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 896;

    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[10] calldata _pubSignals) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, r)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }
            
            // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x, y, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x)
                mstore(add(mIn, 32), y)
                mstore(add(mIn, 64), s)

                success := staticcall(sub(gas(), 2000), 7, mIn, 96, mIn, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 64), mload(pR))
                mstore(add(mIn, 96), mload(add(pR, 32)))

                success := staticcall(sub(gas(), 2000), 6, mIn, 128, pR, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                mstore(_pVk, IC0x)
                mstore(add(_pVk, 32), IC0y)

                // Compute the linear combination vk_x
                
                g1_mulAccC(_pVk, IC1x, IC1y, calldataload(add(pubSignals, 0)))
                
                g1_mulAccC(_pVk, IC2x, IC2y, calldataload(add(pubSignals, 32)))
                
                g1_mulAccC(_pVk, IC3x, IC3y, calldataload(add(pubSignals, 64)))
                
                g1_mulAccC(_pVk, IC4x, IC4y, calldataload(add(pubSignals, 96)))
                
                g1_mulAccC(_pVk, IC5x, IC5y, calldataload(add(pubSignals, 128)))
                
                g1_mulAccC(_pVk, IC6x, IC6y, calldataload(add(pubSignals, 160)))
                
                g1_mulAccC(_pVk, IC7x, IC7y, calldataload(add(pubSignals, 192)))
                
                g1_mulAccC(_pVk, IC8x, IC8y, calldataload(add(pubSignals, 224)))
                
                g1_mulAccC(_pVk, IC9x, IC9y, calldataload(add(pubSignals, 256)))
                
                g1_mulAccC(_pVk, IC10x, IC10y, calldataload(add(pubSignals, 288)))
                

                // -A
                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), mod(sub(q, calldataload(add(pA, 32))), q))

                // B
                mstore(add(_pPairing, 64), calldataload(pB))
                mstore(add(_pPairing, 96), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))

                // alpha1
                mstore(add(_pPairing, 192), alphax)
                mstore(add(_pPairing, 224), alphay)

                // beta2
                mstore(add(_pPairing, 256), betax1)
                mstore(add(_pPairing, 288), betax2)
                mstore(add(_pPairing, 320), betay1)
                mstore(add(_pPairing, 352), betay2)

                // vk_x
                mstore(add(_pPairing, 384), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 416), mload(add(pMem, add(pVk, 32))))


                // gamma2
                mstore(add(_pPairing, 448), gammax1)
                mstore(add(_pPairing, 480), gammax2)
                mstore(add(_pPairing, 512), gammay1)
                mstore(add(_pPairing, 544), gammay2)

                // C
                mstore(add(_pPairing, 576), calldataload(pC))
                mstore(add(_pPairing, 608), calldataload(add(pC, 32)))

                // delta2
                mstore(add(_pPairing, 640), deltax1)
                mstore(add(_pPairing, 672), deltax2)
                mstore(add(_pPairing, 704), deltay1)
                mstore(add(_pPairing, 736), deltay2)


                let success := staticcall(sub(gas(), 2000), 8, _pPairing, 768, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F
            
            checkField(calldataload(add(_pubSignals, 0)))
            
            checkField(calldataload(add(_pubSignals, 32)))
            
            checkField(calldataload(add(_pubSignals, 64)))
            
            checkField(calldataload(add(_pubSignals, 96)))
            
            checkField(calldataload(add(_pubSignals, 128)))
            
            checkField(calldataload(add(_pubSignals, 160)))
            
            checkField(calldataload(add(_pubSignals, 192)))
            
            checkField(calldataload(add(_pubSignals, 224)))
            
            checkField(calldataload(add(_pubSignals, 256)))
            
            checkField(calldataload(add(_pubSignals, 288)))
            

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
             return(0, 0x20)
         }
     }
 }
