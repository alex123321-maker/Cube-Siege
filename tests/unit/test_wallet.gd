extends GutTest

const ResourceWallet = preload("res://scripts/economy/resource_wallet.gd")

func test_wallet_initial_values() -> void:
	var wallet = ResourceWallet.new(20, 10, 5, 2)
	assert_eq(wallet.get_wood(), 20)
	assert_eq(wallet.get_stone(), 10)
	assert_eq(wallet.get_iron(), 5)
	assert_eq(wallet.get_magic_stone(), 2)

func test_wallet_add_resources_emits_signal() -> void:
	var wallet = ResourceWallet.new(10, 5, 2, 0)
	watch_signals(wallet)

	wallet.add_resource(4, 2, 1, 3)
	assert_eq(wallet.get_wood(), 14)
	assert_eq(wallet.get_stone(), 7)
	assert_eq(wallet.get_iron(), 3)
	assert_eq(wallet.get_magic_stone(), 3)
	assert_signal_emitted_with_parameters(wallet, "resources_changed", [14, 7, 3, 3])

func test_wallet_spend_success() -> void:
	var wallet = ResourceWallet.new(10, 5, 2, 3)
	watch_signals(wallet)

	var success: bool = wallet.spend_resources(4, 2, 0, 1)
	assert_true(success, "Spend should succeed when sufficient balance")
	assert_eq(wallet.get_wood(), 6)
	assert_eq(wallet.get_stone(), 3)
	assert_eq(wallet.get_iron(), 2)
	assert_eq(wallet.get_magic_stone(), 2)
	assert_signal_emitted_with_parameters(wallet, "resources_changed", [6, 3, 2, 2])

func test_wallet_spend_insufficient_fails_and_preserves_balance() -> void:
	var wallet = ResourceWallet.new(5, 2, 1, 0)
	watch_signals(wallet)

	var success: bool = wallet.spend_resources(10, 0, 0, 0)
	assert_false(success, "Spend should fail when insufficient balance")
	assert_eq(wallet.get_wood(), 5, "Wood balance should be preserved")
	assert_eq(wallet.get_stone(), 2, "Stone balance should be preserved")
	assert_eq(wallet.get_iron(), 1, "Iron balance should be preserved")
	assert_eq(wallet.get_magic_stone(), 0, "Magic stone balance should be preserved")
	assert_signal_not_emitted(wallet, "resources_changed")

func test_wallet_rejects_negative_amounts() -> void:
	var wallet = ResourceWallet.new(10, 10, 10, 5)
	watch_signals(wallet)

	wallet.add_resource(-5, 0, 0, -2)
	assert_eq(wallet.get_wood(), 10, "Negative add must be rejected")
	assert_eq(wallet.get_magic_stone(), 5, "Negative add must be rejected")

	var spend_neg: bool = wallet.spend_resources(-5, 0, 0, 0)
	assert_false(spend_neg, "Negative spend must be rejected")
	assert_eq(wallet.get_wood(), 10, "Balance must remain unchanged")

func test_wallet_magic_stone_direct() -> void:
	var wallet = ResourceWallet.new()
	assert_eq(wallet.get_magic_stone(), 0, "Default magic stone should be 0")
	wallet.add_resource(0, 0, 0, 2)
	assert_eq(wallet.get_magic_stone(), 2, "Should have 2 magic stones")
	assert_true(wallet.has_resources(0, 0, 0, 2))
	assert_false(wallet.has_resources(0, 0, 0, 3))
	var spent = wallet.spend_resources(0, 0, 0, 1)
	assert_true(spent)
	assert_eq(wallet.get_magic_stone(), 1)
