#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RPC_URL="http://localhost:8545"
FORK_URL="https://rpc.testnet.oasys.games/"
TOKEN_ADDRESS="0x71a778Dae58ac5E68b18f2dD10546eC52eEB217D"
HOLDER_ADDRESS="0xDd7Af8689f967E355Bc0302D525a50FDc75c104d"
YOUR_WALLET="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

echo -e "${YELLOW}🚀 Starting SMP Token Transfer Script${NC}"
echo "================================================"

# Impersonate the holder account
echo -e "${GREEN}2. Impersonating holder account...${NC}"
cast rpc anvil_impersonateAccount $HOLDER_ADDRESS --rpc-url $RPC_URL > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "   Account ${HOLDER_ADDRESS} impersonated ${GREEN}✓${NC}"
else
    echo -e "${RED}   Failed to impersonate account${NC}"
    kill $ANVIL_PID
    exit 1
fi

# Check holder's balance
echo -e "${GREEN}3. Checking holder's balance...${NC}"
BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)" $HOLDER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ -z "$BALANCE" ]; then
    echo -e "${RED}   Failed to get balance${NC}"
    kill $ANVIL_PID
    exit 1
fi

# Convert balance to decimal (assuming 18 decimals)
BALANCE_DEC=$(echo "$BALANCE" | sed 's/0x//' | tr '[:lower:]' '[:upper:]')
BALANCE_HUMAN=$(echo "ibase=16; $BALANCE_DEC / (10^18)" | bc 2>/dev/null || echo "Large amount")

echo -e "   Raw balance: ${YELLOW}$BALANCE${NC}"
echo -e "   Holder has ~${YELLOW}$BALANCE_HUMAN${NC} tokens"

# Check your initial balance
echo -e "${GREEN}4. Checking your initial balance...${NC}"
INITIAL_BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)" $YOUR_WALLET --rpc-url $RPC_URL 2>/dev/null)
echo -e "   Your initial balance: ${YELLOW}$INITIAL_BALANCE${NC}"

# Transfer tokens
echo -e "${GREEN}5. Transferring tokens...${NC}"
TX_HASH=$(cast send $TOKEN_ADDRESS \
  "transfer(address,uint256)" \
  $YOUR_WALLET \
  $BALANCE \
  --from $HOLDER_ADDRESS \
  --rpc-url $RPC_URL \
  --unlocked \
  --json 2>/dev/null | jq -r '.transactionHash' 2>/dev/null)

if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
    # Try without json flag if jq is not installed
    cast send $TOKEN_ADDRESS \
      "transfer(address,uint256)" \
      $YOUR_WALLET \
      $BALANCE \
      --from $HOLDER_ADDRESS \
      --rpc-url $RPC_URL \
      --unlocked > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   Transfer executed ${GREEN}✓${NC}"
    else
        echo -e "${RED}   Transfer failed${NC}"
        kill $ANVIL_PID
        exit 1
    fi
else
    echo -e "   Transaction hash: ${YELLOW}$TX_HASH${NC}"
    echo -e "   Transfer executed ${GREEN}✓${NC}"
fi

# Check your new balance
echo -e "${GREEN}6. Verifying your new balance...${NC}"
NEW_BALANCE=$(cast call $TOKEN_ADDRESS "balanceOf(address)" $YOUR_WALLET --rpc-url $RPC_URL 2>/dev/null)
echo -e "   Your new balance: ${YELLOW}$NEW_BALANCE${NC}"

# Verify transfer success
if [ "$NEW_BALANCE" = "$BALANCE" ]; then
    echo -e "\n${GREEN}🎉 SUCCESS! All tokens transferred to your wallet!${NC}"
else
    echo -e "\n${YELLOW}⚠️  Transfer completed but balances don't match exactly${NC}"
fi

echo "================================================"
echo -e "${YELLOW}Anvil is still running (PID: $ANVIL_PID)${NC}"
echo -e "To stop it, run: ${YELLOW}kill $ANVIL_PID${NC}"
echo -e "To view logs: ${YELLOW}tail -f anvil.log${NC}"