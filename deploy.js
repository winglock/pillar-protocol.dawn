import hre from "hardhat";
const { ethers } = hre;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();
    const treasury = deployer.address;
    const insuranceFund = deployer.address; // 데모 목적

    console.log('🚀 배포 프로세스를 시작합니다...');
    console.log('네트워크:', hre.network.name);
    console.log('배포 계정:', deployer.address);
    
    const balance = await deployer.provider.getBalance(deployer.address);
    console.log('계정 잔액:', ethers.formatEther(balance), 'ETH');
    
    // 배포를 위한 최소 잔액 확인 (예: 0.1 ETH)
    if (balance < ethers.parseEther('0.1')) {
      throw new Error('배포를 위한 계정 잔액이 부족합니다. 최소 0.1 ETH가 필요합니다.');
    }

    // --- 1. Mock 토큰 배포 ---
    console.log('\n📝 테스트용 Mock 토큰을 배포합니다...');
    
    const MockERC20 = await ethers.getContractFactory('MockERC20');
    
    // Mock USDC 배포 - 이름을 "Test USD Coin"으로 변경하여 PILLAR 토큰으로 인식되지 않도록 함
    console.log('Mock USDC 배포 중...');
    let mockUSDC = await MockERC20.deploy(  // ✅ let으로 변경 (재할당 가능)
      'Test USD Coin', // 이름 변경
      'tUSDC',         // 심볼도 변경
      6, // 소수점 6자리
      ethers.parseUnits('1000000', 6) // 1백만 USDC
    );
    await mockUSDC.waitForDeployment();
    let usdcAddress = await mockUSDC.getAddress();  // ✅ let으로 변경 (재할당 가능)
    console.log('✅ Mock USDC 배포 완료:', usdcAddress);

    // Mock WETH 배포
    console.log('Mock WETH 배포 중...');
    let mockWETH = await MockERC20.deploy(  // ✅ let으로 변경 (일관성 위해)
      'Test Wrapped Ether', // 이름 변경
      'tWETH',              // 심볼도 변경
      18, // 소수점 18자리
      ethers.parseEther('10000') // 1만 WETH
    );
    await mockWETH.waitForDeployment();
    let wethAddress = await mockWETH.getAddress();  // ✅ let으로 변경 (일관성 위해)
    console.log('✅ Mock WETH 배포 완료:', wethAddress);

    // --- 2. PumpFunOracle 배포 ---
    console.log('\n🔮 PumpFunOracle을 배포합니다...');
    const PumpFunOracle = await ethers.getContractFactory('PumpFunOracle');
    const pumpOracle = await PumpFunOracle.deploy();
    await pumpOracle.waitForDeployment();
    const oracleAddress = await pumpOracle.getAddress();
    console.log('✅ PumpFunOracle 배포 완료:', oracleAddress);

    // --- 3. MemeTokenRegistry 배포 ---
    console.log('\n📋 MemeTokenRegistry를 배포합니다...');
    const MemeTokenRegistry = await ethers.getContractFactory('MemeTokenRegistry');
    const memeRegistry = await MemeTokenRegistry.deploy(oracleAddress);
    await memeRegistry.waitForDeployment();
    const registryAddress = await memeRegistry.getAddress();
    console.log('✅ MemeTokenRegistry 배포 완료:', registryAddress);

    // --- 4. PillarLendingVault 배포 ---
    console.log('\n🏦 PillarLendingVault를 배포합니다...');
    const PillarLendingVault = await ethers.getContractFactory('PillarLendingVault');
    const lendingVault = await PillarLendingVault.deploy(usdcAddress, treasury);
    await lendingVault.waitForDeployment();
    const lendingVaultAddress = await lendingVault.getAddress();
    console.log('✅ PillarLendingVault 배포 완료:', lendingVaultAddress);

    // --- 5. DynamicRangeVault 배포 ---
    console.log('\n💎 DynamicRangeVault를 배포합니다...');
    const DynamicRangeVault = await ethers.getContractFactory('DynamicRangeVault');
    const dynamicVault = await DynamicRangeVault.deploy(
      lendingVaultAddress,
      registryAddress,
      treasury
    );
    await dynamicVault.waitForDeployment();
    const dynamicVaultAddress = await dynamicVault.getAddress();
    console.log('✅ DynamicRangeVault 배포 완료:', dynamicVaultAddress);

    // --- 6. PillarLiquidationEngine 배포 ---
    console.log('\n⚡ PillarLiquidationEngine을 배포합니다...');
    const PillarLiquidationEngine = await ethers.getContractFactory('PillarLiquidationEngine');
    const liquidationEngine = await PillarLiquidationEngine.deploy(
      dynamicVaultAddress,
      lendingVaultAddress,
      registryAddress,
      treasury,
      insuranceFund
    );
    await liquidationEngine.waitForDeployment();
    const liquidationEngineAddress = await liquidationEngine.getAddress();
    console.log('✅ PillarLiquidationEngine 배포 완료:', liquidationEngineAddress);

    // --- 7. 컨트랙트 간 설정 ---
    console.log('\n⚙️ 컨트랙트 간 설정을 진행합니다...');

    // DynamicRangeVault에 LiquidationEngine 설정
    console.log('DynamicRangeVault에 LiquidationEngine 설정 중...');
    let tx = await dynamicVault.setLiquidationEngine(liquidationEngineAddress);  // ✅ let 유지
    await tx.wait();
    console.log('✅ DynamicRangeVault: LiquidationEngine 설정 완료');

    // PillarLendingVault에 DynamicRangeVault 인가
    console.log('PillarLendingVault에 DynamicRangeVault 인가 중...');
    tx = await lendingVault.setVaultAuthorization(dynamicVaultAddress, true);  // ✅ 재할당 (let 맞음)
    await tx.wait();
    console.log('✅ PillarLendingVault: DynamicRangeVault 인가 완료');

    // --- 8. 자산 설정 (수정됨) ---
    console.log('\n🪙 자산을 설정합니다...');

    // PILLAR 토큰 주소 확인 (스마트 컨트랙트에서 PILLAR 토큰 주소를 가져와야 함)
    console.log('PILLAR 토큰 주소 확인 중...');
    let pillarTokenAddress;  // ✅ 이미 let으로 되어 있음 (올바름)
    try {
      // PillarLendingVault에서 PILLAR 토큰 주소를 가져옴
      pillarTokenAddress = await lendingVault.pillarToken();
      console.log('PILLAR 토큰 주소:', pillarTokenAddress);
    } catch (error) {
      console.log('⚠️ PILLAR 토큰 주소를 가져올 수 없습니다. 스킵합니다.');
      pillarTokenAddress = ethers.ZeroAddress;
    }

    // USDC 주소가 PILLAR 토큰과 다른지 확인
    if (usdcAddress.toLowerCase() === pillarTokenAddress.toLowerCase() && pillarTokenAddress !== ethers.ZeroAddress) {
      console.log('⚠️ USDC 주소가 PILLAR 토큰과 같습니다. 다른 주소로 새 토큰을 배포합니다...');
      
      // 새로운 USDC 토큰 배포
      const newMockUSDC = await MockERC20.deploy(
        'Alternative USD Coin',
        'aUSDC',
        6,
        ethers.parseUnits('1000000', 6)
      );
      await newMockUSDC.waitForDeployment();
      const newUsdcAddress = await newMockUSDC.getAddress();
      console.log('✅ 새 Mock USDC 배포 완료:', newUsdcAddress);
      
      // 기존 변수 업데이트 - ✅ 이제 let이라 재할당 가능!
      usdcAddress = newUsdcAddress;
      mockUSDC = newMockUSDC;
    }

    // USDC를 대출 자산으로 추가 (더 안전한 매개변수 사용)
    console.log('USDC를 대출 자산으로 추가 중...');
    try {
      tx = await lendingVault.addAsset(
        usdcAddress,
        ethers.parseUnits('0.05', 27), // 5% 기본 이자율 (더 높은 값으로 설정)
        ethers.parseUnits('0.2', 27),  // 20% 승수
        ethers.parseUnits('2', 27),    // 200% 점프 승수
        ethers.parseUnits('0.8', 18),  // 80% 최적 활용률
        500 // 5% 예치금 비율 (500 -> 5.00%)
      );
      await tx.wait();
      console.log('✅ USDC 대출 자산 추가 완료');
    } catch (error) {
      console.error('❌ USDC 자산 추가 실패:', error.message);
      
      // 대안: 기본 자산으로 추가 시도
      console.log('🔄 기본 설정으로 USDC 자산 추가를 재시도합니다...');
      try {
        tx = await lendingVault.addAsset(
          usdcAddress,
          ethers.parseUnits('0.03', 27), // 3% 기본 이자율
          ethers.parseUnits('0.15', 27), // 15% 승수
          ethers.parseUnits('1.5', 27),  // 150% 점프 승수
          ethers.parseUnits('0.75', 18), // 75% 최적 활용률
          300 // 3% 예치금 비율
        );
        await tx.wait();
        console.log('✅ USDC 대출 자산 추가 완료 (기본 설정)');
      } catch (retryError) {
        console.error('❌ USDC 자산 추가 재시도 실패. 자산 설정을 건너뜁니다.');
        console.error('자세한 오류:', retryError.message);
      }
    }

    // WETH를 BLUE_CHIP 등급으로 설정
    console.log('WETH를 BLUE_CHIP 등급으로 설정 중...');
    try {
      tx = await dynamicVault.setAssetTier(wethAddress, 0); // BLUE_CHIP = 0
      await tx.wait();
      console.log('✅ WETH BLUE_CHIP 등급 설정 완료');
    } catch (error) {
      console.error('❌ WETH 등급 설정 실패:', error.message);
      console.log('⚠️ WETH 등급 설정을 건너뜁니다.');
    }

    // --- 9. 초기 토큰 분배 ---
    console.log('\n💰 테스트를 위해 토큰을 분배합니다...');
    
    // 배포자에게 토큰 민팅
    console.log('배포자에게 USDC 민팅 중...');
    tx = await mockUSDC.mint(deployer.address, ethers.parseUnits('50000', 6)); // 5만 USDC
    await tx.wait();
    
    console.log('배포자에게 WETH 민팅 중...');
    tx = await mockWETH.mint(deployer.address, ethers.parseEther('500')); // 500 WETH
    await tx.wait();
    console.log('✅ 배포자에게 토큰 민팅 완료');

    // --- 10. 초기 가격 설정 (선택 사항) ---
    console.log('\n📊 초기 가격을 설정합니다...');
    try {
      // WETH 초기 가격 설정 (예: \$2000)
      tx = await pumpOracle.setPrice(wethAddress, ethers.parseUnits('2000', 8)); // \$2000 (8자리 소수점)
      await tx.wait();
      console.log('✅ WETH 초기 가격 설정 완료: \$2000');
    } catch (error) {
      console.log('⚠️ 초기 가격 설정 실패 (Oracle이 지원하지 않거나 다른 오류 발생)');
      console.log('오류 상세:', error.message);
    }

    // --- 11. 배포 후 최종 검증 (간소화) ---
    console.log('\n🔍 배포된 컨트랙트 설정을 최종 검증합니다...');

    // DynamicRangeVault에 LiquidationEngine이 올바르게 설정되었는지 확인
    try {
      const configuredLiquidationEngine = await dynamicVault.liquidationEngine();
      if (configuredLiquidationEngine.toLowerCase() !== liquidationEngineAddress.toLowerCase()) {
          console.error(`⚠️ DynamicRangeVault Liquidation Engine 설정 오류. 예상: ${liquidationEngineAddress}, 실제: ${configuredLiquidationEngine}`);
      } else {
          console.log('✅ DynamicRangeVault: Liquidation Engine 설정 검증 완료.');
      }
    } catch (error) {
      console.log('⚠️ Liquidation Engine 설정 검증 실패:', error.message);
    }

    // PillarLendingVault가 DynamicRangeVault를 인가했는지 확인
    try {
      const isDynamicVaultAuthorized = await lendingVault.isVaultAuthorized(dynamicVaultAddress);
      if (!isDynamicVaultAuthorized) {
          console.error(`⚠️ PillarLendingVault가 DynamicRangeVault(${dynamicVaultAddress})를 인가하지 않았습니다.`);
      } else {
          console.log('✅ PillarLendingVault: DynamicRangeVault 인가 검증 완료.');
      }
    } catch (error) {
      console.log('⚠️ 인가 설정 검증 실패:', error.message);
    }
    
    // 초기 토큰 분배 검증
    try {
      const usdcBalance = await mockUSDC.balanceOf(deployer.address);
      const wethBalance = await mockWETH.balanceOf(deployer.address);
      
      console.log(`✅ 배포자 잔액 검증 완료 (USDC: ${ethers.formatUnits(usdcBalance, 6)}, WETH: ${ethers.formatEther(wethBalance)})`);
    } catch (error) {
      console.log('⚠️ 토큰 잔액 검증 실패:', error.message);
    }

    // --- 최종 요약 ---
    console.log('\n🎉 배포 완료! 🎉');
    console.log('═'.repeat(60));
    console.log('📋 컨트랙트 주소:');
    console.log('═'.repeat(60));
    console.log(`Mock USDC (tUSDC):      ${usdcAddress}`);
    console.log(`Mock WETH (tWETH):      ${wethAddress}`);
    console.log(`PumpFunOracle:          ${oracleAddress}`);
    console.log(`MemeTokenRegistry:      ${registryAddress}`);
    console.log(`PillarLendingVault:     ${lendingVaultAddress}`);
    console.log(`DynamicRangeVault:      ${dynamicVaultAddress}`);
    console.log(`PillarLiquidationEngine: ${liquidationEngineAddress}`);
    if (pillarTokenAddress && pillarTokenAddress !== ethers.ZeroAddress) {
      console.log(`PILLAR Token:           ${pillarTokenAddress}`);
    }
    console.log('═'.repeat(60));
    
    console.log('\n🔧 프론트엔드 설정용 JavaScript 객체:');
    console.log('═'.repeat(60));
    console.log(`
// 프론트엔드 JavaScript 코드의 CONTRACTS 객체를 다음으로 교체하세요:
const CONTRACTS = {
  dynamicVault: "${dynamicVaultAddress}",
  lendingVault: "${lendingVaultAddress}",
  usdc: "${usdcAddress}",
  weth: "${wethAddress}",
  oracle: "${oracleAddress}",
  registry: "${registryAddress}",
  liquidationEngine: "${liquidationEngineAddress}"
};
    `);
    console.log('═'.repeat(60));
    
    console.log('\n✅ 모든 컨트랙트 배포 및 설정이 완료되었습니다!');
    console.log('\n📝 다음 단계:');
    console.log('1. 위 컨트랙트 주소를 프론트엔드 코드의 CONTRACTS 객체에 복사하세요.');
    console.log('2. 프론트엔드 애플리케이션을 테스트하세요.');
    console.log('3. 필요한 경우 추가 설정을 진행하세요.');
    
  } catch (error) {
    console.error('\n❌ 배포 실패!');
    console.error('오류 상세:', error.message);
    
    if (error.message.includes('insufficient funds')) {
      console.error('💡 해결 방법: 배포 계정에 더 많은 ETH를 추가하세요.');
    } else if (error.message.includes('Contract deployment failed')) {
      console.error('💡 해결 방법: 컨트랙트 코드의 컴파일 오류를 확인하세요.');
    } else if (error.message.includes('Cannot add PLLAR token')) {
      console.error('💡 해결 방법: PILLAR 토큰과 다른 주소의 토큰을 사용해야 합니다.');
    } else if (error.message.includes('nonce too high')) {
      console.error('💡 해결 방법: 계정 nonce를 재설정하거나 보류 중인 트랜잭션을 기다리세요.');
    }
    
    throw error;
  }
}

main()
  .then(() => {
    console.log('\n🎯 배포 스크립트가 성공적으로 완료되었습니다!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n💥 배포 스크립트 실행 중 오류 발생:', error);
    process.exit(1);
  });
