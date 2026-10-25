# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "digest"
require "minitest/autorun"

# Local mandatory gate; the existing release workflow is deliberately unchanged.
class BlizzardRuntimeBoundaryTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  BASELINE = "0830294eff5b8cd86324545ed00689648c70bd23"
  AURORA_BASELINE = "521274b84c55b15027de43bf2d6c28fe85731cb5"
  CURRENT_PATCH_BASE = "b37b073eef2be19f2534443469c4fd22e7238463"
  CURRENT_PATCH_SNAPSHOT = "bb5f0414ec3a42c5e9ea42414410d2566f445e75"
  LUMA_BASELINE = "20dd0b98fddee2480ca51c78c29eedffe5e61ae3"
  LUMA_SOURCE_SHA256 = {
    "assets/translations/ar.i18n.json" => ["a6fbd8c59b143bbbf0ff6a73de93811694b8b5b20431aa37c08ca4f590bed7d7", "0c1bb67ebfe5cfe98b5901f22f35760cbd13d9ef507e7c136fa5aa62a04763ba"],
    "assets/translations/en.i18n.json" => ["c8620bce25da968f9af9d6ee5c2433487556032a754638331673b35c6e482dfa", "5ad02ef46b6dd6ee358ebf0573c43050952af619a94972cf428eef1da5d16186"],
    "assets/translations/es.i18n.json" => ["0780670756eab83422ba65a0d1bedd41bd88fa1d6c8d20c420f7628511535dee", "b894d877ce7a28f1123416d8a53b4095a3fb5fbf720688139e637949e21ef7b9"],
    "assets/translations/fa.i18n.json" => ["fea6ae9e20c864b7b81659248188a90b25ccd6350f5897ba506e05a989753598", "dbd2090305a3c4389b5f3da24d2498aaa65947ffca298d932ac5e6eb483eb47f"],
    "assets/translations/fr.i18n.json" => ["179eb7dfbb95008b3edbb70fdc9933d34515d45ac0e48ae37d9a2dbe56e17105", "0dd0ca21283023a6fea03f928a64fd1eda6137f3844430f9973bd4b0a9a2eabd"],
    "assets/translations/id.i18n.json" => ["a2002e2475de085559818056fad9756438dc0ad2ad9f0a2789a7e20b8e8d08fc", "5f76b74fd0cf151a059fab67935f630c4d29ebdba060fb38423bdaf3ca74717e"],
    "assets/translations/pt-BR.i18n.json" => ["42fa63bacb8a0cb88837466baba7cc98f5a77a73c63c161fd41ed8bf8497087b", "7afc484b382d75036b01cb0fcad4309980d80c81a8b1dff2b147ec7c53fd2700"],
    "assets/translations/ru.i18n.json" => ["214b34c544c0135d90a252b36b525a15ebcabe654b28861a6ebf38ff7fcba1c6", "4c33c320440116916610cc9150a5be1866a35575b8536adf8f2c9d101625766b"],
    "assets/translations/tr.i18n.json" => ["204c646109a7c0c2f68682c409a09765282ab85007a63f83d2e43bbe49856f20", "e8b103c74ad29fe7cb3a396791fa3d6a795b13bd082012cd00dc2ea06c2a4f8a"],
    "assets/translations/zh-CN.i18n.json" => ["bf453713a0c27e7f793425610aac9fd5559c916648a593f604da1e9ec8e475ea", "57d888ae299a31224268a89e3a4002afbf860a65b29672ea60ada0e88194510e"],
    "assets/translations/zh-TW.i18n.json" => ["fe981657dcc65112fad1fa49523502f4965c73a8b3d230cc89dcb9af7c95f2c0", "d251f272c21e74d5d67dc448497b1eeb739320291d9592a94edcf5de14c17062"],
    "ios/Runner/BlizzardNativeGlass.swift" => ["7fdd5dd3dd3799b132594563827ff9d7b826312c0e818a42cb15f16c1ad82b73", "b647bd6534d5c0378231a1f5a5d2f153a9a70d6414bae76a91cb1d3535d75578"],
    "ios/Runner/Info.plist" => ["e470873245ee919499c8b57d4ff6b46014467ad4a8009056c0347158a3e86c2e", "1532dadaaab36a1f8af9b19d495cf130d4fff49437bbb370be081fc013593391"],
    "ios/Runner/VPN/VPNManager.swift" => ["11e7e1a8144deb25e4909141d20fe95b7013c01df132c477e975cfe5cba773d6", "9d318b144ce4555f9f9040424d9f1aad208bc7a7d5d3fdd2434a807dda5f67f6"],
    "ios/RunnerTests/RunnerTests.swift" => ["2191aa1ee55b1dd9af68580be04ed1ca8dfc4f4fca242a16095b8c9822142c32", "2c510b5bef6c422cac6ddcf2ff2a244fad2565131016a92db7ea3538c83015ce"],
    "ios/packaging/ios/make_config.yaml" => ["fd7d933448cdf0c7184f14e3d0475c82aa719bf9990af15abe9ef683ac3b6a68", "7494b9f5f15554ef12954728aeec394cb040f6df75157cc937b8c370094858ba"],
    "lib/core/model/constants.dart" => ["da33cdb4b668428371bf8749d718d132571b175d79324e98b1f3fad9ef6895d8", "1c04d375d6b7e2de7e7cea8ca0bc6e9323596a6d552d6d666ed8dd1c5c1c006c"],
    "lib/core/router/dialog/widgets/warp_license_dialog.dart" => ["350f6214ce1d42a36c102f14e602bc91b44f52604a8adf6453747c92fb24fb5f", "f1a53a0fb396f8ea7e4b0723c7d0746f064fbe1db0711b6d74abff6f35baebbe"],
    "lib/core/widget/blizzard/blizzard_glass.dart" => ["6981e714810ac61ac145b22c6e1c95a7af85dd5836ff2d0d76e3785e77ebc98f", "d18aa2d90380d9d0a89b903110c80ae9ad880bdce66622f8c8812c2ceafdbeb9"],
    "lib/core/widget/blizzard/blizzard_scene.dart" => ["563fe4292896464bc4d3adb5d860ea584992299d50a2c282a9cc6312589baf9c", "68415a2ab8a3cc4ac6fa07939fd870868aedc2126b345706ec3c8f81ea5c0bfc"],
    "lib/features/about/widget/about_page.dart" => ["4493cca192157403298dd6840b2ce6e54ca14b8b6e97f144dff687aa3048bd8d", "cc0939dd3968a2479fedcf7892a2d32fe1ab627a86170156e0c1c27c052b8917"],
    "lib/features/common/qr_code_scanner_screen.dart" => ["6230ebc29d243eec8a8eac86272123373076485c9847578cb5644423cd0e067a", "e863aab13421d04231156d941ffcb929da0ac0177bce9bb7f813b0d0443872f7"],
    "lib/features/diagnostics/safe_diagnostics_page.dart" => ["a0517affe958c607b6bc1f97abdf16302b38553f5ed3ef0391fa279e1de21ae0", "f7e7e6123d3987f7fbeb6fd445e1283cf3f8e1a78b0e571e6e56e0943976291e"],
    "lib/features/home/widget/connection_button.dart" => ["38c4776a78d4501859929078f96c796f9b0184fbe10e64be3b7c381c32f06d90", "50a09b71598c4970575a6585f7c50c721ab0c5c1e9108ef7e59545c7ff6dfb50"],
    "lib/features/home/widget/home_page.dart" => ["ed1b83192d6881cabd2d597e28f260e4871b86d48a6b88d0893ad1cd3f821a9d", "6912dceb425f3089bdc1bc8ca2b9bb08fdf295514db635080086eec183738e92"],
    "lib/features/intro/widget/intro_page.dart" => ["418690f53dfeac37466ad3531b9756cc10b04f0e967a73b7f1368f7c0d592fc9", "f23de216dc9fa279201d9a5909ea75942f529c5bb1b4096018366e1e607d4701"],
    "lib/features/profile/details/json_editor.dart" => ["225a22720c511571af57afb01c5c5879904acc46d977fb01b188e65fff0828c7", "59372c670a1480f68cdb8c152eeaedafbaf26f287bd747c45fb07225e7cae613"],
    "lib/features/profile/details/profile_details_page.dart" => ["8d1aa8d4dab4394752b08901e91b6b1b0d5d14f9b97a8b67d5fe3a46f77ed512", "332dee2b4017f4644dd17f9cff103aaba5875861c26121189d2ee60de7a1a093"],
    "lib/features/proxy/overview/proxies_overview_page.dart" => ["5eca17f8150a9564c8909451fcbfb73e82ee57e8168b41a589c0e1d507095051", "f5952e407fd07eac490ecd896dd1b94e055ea2d01426552adeb62c4c4a66db4b"],
    "lib/features/settings/widget/blizzard_settings_leading.dart" => ["67fcc949da27fdee8ca2737346a64b6e9b404f57d29a9e87dd0fcb736118781e", "77fac170b15af0199ba17f1e42e72c86619853324d90e577a3b144a988b1897a"],
    "pubspec.yaml" => ["bb87d6dc780627d07b85303d2d8343629d602fc65c7c9125179040d268a39b3e", "98e742bb71846eb2636906e7ebf0da786325b08eaa2583587822360cfaa3261f"],
  }.freeze
  LUMA_NEW_SHA256 = {
    "assets/shaders/blizzard_aurora_soft.frag" => "00c76ab64fd55d3d17cccdf0f3f0f2234673e8f7e372bd6ec19a084498dc7a9a",
    "lib/core/widget/blizzard/blizzard_toolbar.dart" => "d25f00afb210ac4c43f8ec7be2fdc22c7dff7b68295fe0bba589c4df2879fb49",
  }.freeze
  CURRENT_PATCH_SOURCE_SHA256 = {
    "assets/shaders/blizzard_aurora.frag" => ["791f6f1c746fedb7df411df9bcc70516ef5e5ff46a4c5ade9c1a55c81026fa47", "7a7bc6dc56a67b2cf5eafe62005e72c3eb015db7c84dc5fde9187dcf2517d569"],
    "ios/HiddifyPacketTunnel/Logger.swift" => ["dd25284df008b05268740bbd720969eb337982eece068819002a20b8a58a8964", "a3802f5c49754211fd2fa3192669b2103e719903b24b5e9cb420388f9f68a1b8"],
    "ios/HiddifyPacketTunnel/SingBox/ExtensionPlatformInterface.swift" => ["00350de3fba1275eb07c3dcf3ed37072dcd2e2a68a878281ee6ef66577b354df", "590db29633fb15448adebf1a22bf4b7003273d48cd1926225f29fc501a5f2b7c"],
    "ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift" => ["8876aae20b2e98c0cef2abf66b82080461f770e5b007d0eba9ff547e9880f4aa", "02b962decf322a62bcb0bb7292604b10a842c016bd5b25f922639c5154404e9c"],
    "ios/Runner/BlizzardNativeGlass.swift" => ["7146266a649f81c57218352c2027293f0834bef7f11dc1d2fa0bb1891b8752bd", "7fdd5dd3dd3799b132594563827ff9d7b826312c0e818a42cb15f16c1ad82b73"],
    "ios/Runner/Handlers/MethodHandler.swift" => ["0b31cee80b348c6e3cbf31bf0abc9187d58d0665ccbbde81758fd03813ae1195", "21a65e381514d998ec27ac720af72dfb13689a8f0a481def0bfb0c4a9bb8f059"],
    "ios/Runner/VPN/VPNManager.swift" => ["9b69434490e99cb68c93d55c1d3ffcedb2da08f5007a8de94cd390651789aa1d", "11e7e1a8144deb25e4909141d20fe95b7013c01df132c477e975cfe5cba773d6"],
    "ios/RunnerTests/RunnerTests.swift" => ["a3a1d68fab21168cb784f7004c2f9088a7ea102c9a0972aaa427a8a883d44a75", "2191aa1ee55b1dd9af68580be04ed1ca8dfc4f4fca242a16095b8c9822142c32"],
    "lib/core/analytics/analytics_controller.dart" => ["79f392ac842f14a1fd648710f32d17d4d7dd46121cf9e62a67e8386805c15cf1", "243109a830cde1662db393f3eb7ed20152bacd60b4c06f02604afdba80d59f31"],
    "lib/core/http_client/dio_http_client.dart" => ["7e8ec4f0d4c55c03e076fcd47fa64589e06cc8ff8cf734e4d1e59aa5704c12a8", "964b5484d484b86d9172a8f2c93eb3fa0ee7724d4a6d74c89b3a842a39d695a4"],
    "lib/core/observability/better_stack_log_printer.dart" => ["057f082efdff763fa32e4f30b2c8d3d67f4172b85378bdd324bf8c10358a7d2d", "45a2d45cde98e4ae798ea251fba7b5efef61e91290ebbfaf276295e47202cbdf"],
    "lib/core/observability/telemetry_transport_attempt.dart" => ["fae673488fac9136afd74072a8c4224f5099750cd234862952b305eaa113ddaa", "71f7694ccaeed995d4e952b3f58890e3358dcd5691d35c9bcf9259eaf302c483"],
    "lib/core/router/adaptive_layout/my_adaptive_layout.dart" => ["0993a837bc61074114124b4a6128255900407fa9709de817aaba2fdf94a23d70", "40b114e8e92a3956883183a325a82e6c14bd48d02c175dae5f672ea3a0d1e302"],
    "lib/core/widget/blizzard/blizzard_native_connection_control.dart" => ["79febb26929447e76ffbf84ecf945fae6641a32fc5c6b4480f3fd6319f44ad0d", "6479e1ba6b12b700724a3e8c75e6bff437bac7ad0bacc30931f01ed24e2f20ac"],
    "lib/core/widget/blizzard/blizzard_scene.dart" => ["cf782ff9802261a1ea646fab813c98b0eddb204e8ca2a0dfc3e251f0d953e823", "563fe4292896464bc4d3adb5d860ea584992299d50a2c282a9cc6312589baf9c"],
    "lib/features/connection/data/connection_repository.dart" => ["2617799913ec1784e331ae093fdfd7923f9b73b156c38012329fe5c4b655cd25", "bf19e980c87857183d238beefc9879b44d4f3a085e035819e0bb0ee88de41ee9"],
    "lib/features/connection/notifier/connection_notifier.dart" => ["11e86128c2d8604089087be05f807129973e52823180fcfa5b528c6e8ba0a26d", "efd46a4a99c7d3d50a7eadcab0cea0e12e8741210fc5ec39324447034451ef17"],
    "lib/features/diagnostics/diagnostic_providers.dart" => ["ccbd9164f42ef63602b640de0ce0c5e35f81bf2f3dcaafca07351ccd16a2be75", "d9df79e2f5ed12145114eb5aaff82abe5df2328817372c15a84b355e69018b00"],
    "lib/features/diagnostics/observed_connection_repository.dart" => ["8bd1bdcc05099863f93641b08a16a21e3d3b209f0736ea1cb9df35fc922e8cb1", "aec757c7c2c18a91b60772d77057ef39c04cee2caaebfa6d3791067243755a3e"],
    "lib/features/diagnostics/remote_diagnostic_subscription.dart" => ["d9d386c45564403e69be4a43163388f3189caab4da5b86518bf6c99bc23a3e5c", "281da7b993dd48fc0e500c85d6fd0f25693e3b192e45e0d3dbd87e6ac10a488c"],
    "lib/features/diagnostics/safe_diagnostic_event.dart" => ["867a3fc3c57f729b0de11787f130e18ed2cabc66cbfd36a3344a3a9f1e7a66a6", "6673f3cc2693bbfe3fa1bc9c74910ea15c243d0795f2c188b2c7f36efe0d393e"],
    "lib/features/diagnostics/safe_diagnostic_journal.dart" => ["b84f1dca5f57aee57a7cc2658306038909a48c7eb2b71a00a5c427dcd346f364", "e8f229e5412945819bf0436f2c348f65db8d66e7cb577ebd5a5831fa635c7e4c"],
    "lib/features/diagnostics/safe_diagnostics_page.dart" => ["84f5b28143b9da69c20b753b7b1c6b57c8bddb18c8821b3e6fde4d097ceae780", "a0517affe958c607b6bc1f97abdf16302b38553f5ed3ef0391fa279e1de21ae0"],
    "lib/features/profile/data/profile_data_providers.dart" => ["97b37bec8f4ad95bc4c727b65b7ead189ae0355cadd96528974683e7ec42fe0c", "ca55bd9327d4e352afe59752ae32cefc3de9049595a0c391554347b93366add8"],
    "lib/features/profile/data/profile_parser.dart" => ["30a03e3a1c63daf4f4381a3d1fb47940480a02598bad2ae92b1beb651713b24d", "c010925e21fc63fa07a6a2576d5f3469cb8ac8aa95f54e2de04be40b55c28ebd"],
    "lib/features/profile/data/profile_repository.dart" => ["3079cdfd5280ee8bb33ea416ebc4da11a8a8c20b52734b12514b6cac7b8862f7", "022a7ce6f409032f9912d64d834f775a561762d98f2481ba51ed3781ceda532b"],
    "lib/features/profile/notifier/profile_notifier.dart" => ["881772e9bed7929af0d86d14a3cb321dacb52580d2414e1db16ed4fd7e0db0ac", "603dc606dfbb64f67293aacf021249af496a521098e996712edf79a68132019c"],
    "lib/features/profile/notifier/profiles_update_notifier.dart" => ["2756287291b0f131238c5014684764f0a1a393f2f9e86aac8174dc3140b6e584", "1cdfa3f970d3c3df749e34a0f31566031b11a9563a8fa0a3edcf30963463b068"],
    "lib/features/profile/overview/profiles_modal.dart" => ["a37a0fa9ba9080c654e0ffde21e16ae65b235fc4033d0d5bcb84a74e8915d20e", "03d48126feceb367c118df58da6696c5a280872ec8f640c1e5cb811efdc25a36"],
    "lib/features/proxy/overview/proxies_overview_page.dart" => ["f8756f9a72ba34d20d6e4b6749e5c9059f9b9a9aa57fb4930dd9bf44982198b2", "5eca17f8150a9564c8909451fcbfb73e82ee57e8168b41a589c0e1d507095051"],
    "lib/features/proxy/widget/country_iso_badge.dart" => ["a264f549554718f118094fa65de2d6360b106c3835d899eea976f0ca7243d7be", "6b7b3e0e83b6c5a39569ab3ec884a0228a8e3631904fd42fb055fc15afed66c8"],
    "lib/features/settings/overview/sections/dns_options_page.dart" => ["9449be02318e2afd987e0b0e0e275e1162d93acc86aa4131979b3951fd60f883", "badf1c59d02a15989bf9edfffc73c9aab0812b54f17eb7ea1e13b6298e18ff17"],
    "lib/features/settings/overview/sections/general_page.dart" => ["be55bda6f775f55e2d7d997d24eaf93f77636c4911b71fba15288d9d5c931bf7", "f4e7d2863c179e82c73775aa0008819a5a0261f2e5b0d63ef5053f66b7b895fb"],
    "lib/features/settings/overview/sections/inbound_options_page.dart" => ["42b0063d77902578758e6679fb8f7318b9846994bbb5091a3056eba062aa067d", "552e733fc23a0c1a8ebee1611d09073a82988bf7401d3587fb9332cd346477a6"],
    "lib/features/settings/overview/sections/route_options_page.dart" => ["21d21df975c71a75a95a49441e939f089def0ef2cc0f0f0eee83e4e566b9339d", "8ac97f1cb906268b30963a8b446feafdf4e3e144c6db8670456c8a2706d89bcb"],
    "lib/features/settings/overview/sections/tls_tricks_page.dart" => ["2e88a4f024c5be4afd8d34a767473d06a17f023c5b9ed484965807167d3dd7a3", "9810ac52b92cb47f619a6646124ae86b95ae903966c0052b64605f65544dc418"],
    "lib/features/settings/overview/sections/warp_options_page.dart" => ["f67421feb74daac3414c9668ca2182a763891ced171750616dc03ad4a5eafc8d", "9a6639e7620ae92a0bbef748b05f790de3d08d9e7ae0bff410e9e61dd4a0efd8"],
    "lib/features/settings/overview/settings_page.dart" => ["7b8ad5ccc13557eafb722138103fc2eceea55252251d42cdcfff5ce337952cbd", "771edd69643a9fbf44fc97a3a935bea2220c5441d2fadcdea552c8156e472654"],
    "lib/hiddifycore/hiddify_core_service.dart" => ["b6b1be09d437eab148d494dfb5e784896493f1d4fc71ea1e64ce699cab06aee4", "9b6eab37f35faa504292ba36b9276e9fa8a72dd9c8d252671d741fb83a8301db"],
  }.freeze
  CURRENT_PATCH_NEW_SHA256 = {
    "lib/features/diagnostics/connection_diagnostic_scope.dart" => "1773012caf7ecec372df461c5fa743a9bee826233616ac8ecb924cfa2698f8bf",
    "lib/features/diagnostics/native_diagnostic_importer.dart" => "6d3e58225718bc2427c9968453b266c764d27f8a197d277648b1ff1ef5aa4c0c",
    "lib/features/settings/widget/blizzard_settings_group.dart" => "ef33e3a493226519b76cdda09f38aa13865c9b71c933827acbd5871a1f2c1040",
    "lib/features/settings/widget/blizzard_settings_leading.dart" => "67fcc949da27fdee8ca2737346a64b6e9b404f57d29a9e87dd0fcb736118781e",
  }.freeze
  AURORA_CHANGE_SHA256 = {
    "integration_test/blizzard_native_glass_optics_test.dart" => ["f2f6cab58d488ecf03cd4b7f5623e727a2a35a26b3d8d6c4e99c6c1522d9bf16", "6efacb3957e61f61dd39b9d3b1a552292ef6868358f2eb05ea90fe06e1fc3a79"],
    "integration_test/blizzard_visual_acceptance_test.dart" => ["6871b42eb08b9d7e874610c7143a76672c3975781d708ce9b659ed236903a16f", "6620bbab1714c007a42b4637642d5923672f4b07ed6bed9dd9bb7fac2ad8d349"],
    "ios/Runner.xcodeproj/project.pbxproj" => ["221630aace49cfa805c367e231bed8fc86318a17060e4f53efd8398f9c3edf51", "460047d8adb9838750dd4f3246f03e7acc5f19aa91354cb4f15414bbf10a70cc"],
    "ios/Runner/AppDelegate.swift" => ["ca0e72cb2f3c87edbb25f49b0701b322ff968b74775d6622eb3a4a5a5d4be895", "47fbb97f41b94df40ead7770ee83f96a93962a040767afd20b065de87ebcd592"],
    "ios/Runner/BlizzardNativeGlass.swift" => ["23ef7a0c8f086cb0b4a116e72b16a5d676a1ea489d427c3931ab58481b307e93", "7146266a649f81c57218352c2027293f0834bef7f11dc1d2fa0bb1891b8752bd"],
    "ios/RunnerTests/RunnerTests.swift" => ["8463f988b9823e3414cf7227f66068eba654bee63d2ec00ae95eca0bc00eace9", "a3a1d68fab21168cb784f7004c2f9088a7ea102c9a0972aaa427a8a883d44a75"],
    "lib/core/observability/telemetry_budget.dart" => ["c4629e2840eaf8e5701b7d05b80df8d26d66caa823ccb4cf2aa90ff016a212fd", "5b2a9a9f66c60022c2c571796f893cc06367f5ba52b4928edd234f54236e2a88"],
    "lib/core/router/adaptive_layout/my_adaptive_layout.dart" => ["a33e73521768cc621e016a2429b2362aaa50b4c8002d39a38b2f20f250ba844e", "0993a837bc61074114124b4a6128255900407fa9709de817aaba2fdf94a23d70"],
    "lib/core/router/bottom_sheets/widgets/quick_settings_modal.dart" => ["95a92dc2b5c7ae1508152911840ed54073725d2b5424399931f2aa889ba01d4b", "b660a39d62ce160448dfc17069099f4fb7b708de5e763b9399f2e0c0f6933b82"],
    "lib/core/theme/blizzard_tokens.dart" => ["16d379f55f67f16501161348d626c61f2c84e5a55c2c1e441724233abefd108e", "5ea9b4ca58617d285c9fc111944d4ef82bd5eb56edbfd6f84a6e565e4aa89063"],
    "lib/core/widget/adaptive_menu.dart" => ["d8d0106308ae860b3adc35e859f285ca0ea24e87466e60f5a707a1feebbdf9d5", "0de0ac5885a9e5494e8f8b46f01d9d450f6e5a2c4672f292e621756367bacd58"],
    "lib/core/widget/blizzard/blizzard_glass.dart" => ["86013090a7ca1041345ac20670aeb7ee04cd77f6e308216eb0a13f01ad36b1e7", "6981e714810ac61ac145b22c6e1c95a7af85dd5836ff2d0d76e3785e77ebc98f"],
    "lib/core/widget/blizzard/blizzard_scene.dart" => ["ec02abde5207ef868fff0b93c11ded045fcbcf7a7de8baa5626e5793dc71f996", "cf782ff9802261a1ea646fab813c98b0eddb204e8ca2a0dfc3e251f0d953e823"],
    "lib/features/common/general_pref_tiles.dart" => ["b137691819e315d04acaa8515072b12081c236835272fd54d434463a5a841176", "93f833c376e30cc3009877e108e5716b4f5429ec74b8688fab53ed7efb3162bc"],
    "lib/features/common/qr_code_scanner_screen.dart" => ["2d0f9dd2ce82bd6d6624df85a94b947e305def3a404258e2f80709ca10b2ad78", "6230ebc29d243eec8a8eac86272123373076485c9847578cb5644423cd0e067a"],
    "lib/features/connection/data/connection_repository.dart" => ["b8247270dd21d92df1fefa23ea856c3ca7d4529e8ecc8fba08884aedbc76ccfb", "2617799913ec1784e331ae093fdfd7923f9b73b156c38012329fe5c4b655cd25"],
    "lib/features/diagnostics/safe_diagnostics_page.dart" => ["fd67115e1ee31f249456797775b933f1148a739d260fffb9ab26bb85314a4451", "84f5b28143b9da69c20b753b7b1c6b57c8bddb18c8821b3e6fde4d097ceae780"],
    "lib/features/home/widget/connection_button.dart" => ["df2a0eca77981445ac96f53ad640d610e2ec72489afd9b7bdba169f6cd8b1201", "38c4776a78d4501859929078f96c796f9b0184fbe10e64be3b7c381c32f06d90"],
    "lib/features/home/widget/home_page.dart" => ["49e57ff2729c3a5b4a160dcfa5ed7fed41379944af43785a65d38c113bc9dba5", "ed1b83192d6881cabd2d597e28f260e4871b86d48a6b88d0893ad1cd3f821a9d"],
    "lib/features/profile/add/add_profile_modal.dart" => ["d15b8ec0717495b3341ea55508dcd480fdaa88df58fb3c1845ded4bda85f62ed", "fd4cb1d67480d7eb2f271292cd3b4b3a41e02f7c4e75069b634083462a3e13fa"],
    "lib/features/profile/add/widgets/fix_btn.dart" => ["2bc072d6111ab4cc9c7952337216be77cfae435c79e5a2284b003317ba39e50a", "6a9d736d9a905a0b62237928365401631015a73243ceebf6c81605442efb01fe"],
    "lib/features/profile/details/json_editor.dart" => ["ed820ac98d12c7aace1bfbd0b431a65205799c769d934b2fd6416714624b06b0", "225a22720c511571af57afb01c5c5879904acc46d977fb01b188e65fff0828c7"],
    "lib/features/profile/details/profile_details_page.dart" => ["ac7bf330108af25e9f0207bd47364348cfce2e143e66f2660430939bc8c5a774", "8d1aa8d4dab4394752b08901e91b6b1b0d5d14f9b97a8b67d5fe3a46f77ed512"],
    "lib/features/profile/overview/profiles_modal.dart" => ["9dd9c72b44651a66441f558f78114fc6ca3ccf2d600272c7ad74f14fae4fc065", "a37a0fa9ba9080c654e0ffde21e16ae65b235fc4033d0d5bcb84a74e8915d20e"],
    "lib/features/profile/overview/profiles_page.dart" => ["d02ec9d9b39a1fd7f19f30bf1ba0d6dc8f9549046dd749e277f056fe97add0e2", "d42742986b0394b3aa91aaa8f0d348ea3feb669dafcdd7d1e46956d25d37ae05"],
    "lib/features/profile/widget/profile_tile.dart" => ["ebc8c137502121ca9aa945e9ee9692a02698e84f9f0857947d7c38a6cc3d3e48", "b8824e417b2d2d0cd07decde0e5520bd77d749405f6c1805f6e8401121f285ee"],
    "lib/features/proxy/active/active_proxy_card.dart" => ["889c4f0c4ee4305f68d65f875bd60cbd5e7fb83c00e1d020d1506212dce211f7", "0da9e261ffd0cb4e2f6998e8367de34b40634b16fc023fe1814d63567a34c98b"],
    "lib/features/proxy/active/ios_active_proxy_delay_indicator.dart" => ["d6588aa877c9b3d0003a3738f34c31e2c9c2dc65474693c8f858c28ba46cfd86", "b0266673fbdb13e57ef852c8966723b0a55e7d61dc493c17d05f03067619e428"],
    "lib/features/proxy/widget/proxy_tile.dart" => ["2cb3a3408d63066e23e131f74ee3d9289fdb60077be2524b0b28d1f23321a8ca", "a3e9e3b4543dd191d02c0af6435cbd66fd7eb844871a845242857e64bfc4d703"],
    "lib/features/route_rules/overview/generic_list_page.dart" => ["f0b89ce8a55a210fa3d82116cb6b998188775651f944698db5ebe8950bcf95a6", "f18fd81edf1c33e007d41f81e253e521f9fa118ba7529064713e0513e47256ac"],
    "lib/features/route_rules/overview/rule_page.dart" => ["db2c0f8168c02dc8079749608f1e5a069c63e2a4dc2beb75cd0ade2d8fb39433", "d5c2bef091637c1bbfd8e691b7186594dd96cdd137cfda1eefc6fcf7fa19adca"],
    "lib/features/route_rules/overview/rules_page.dart" => ["7542a940d382f5368364a15088dfff9918107130344b29b48cad3e4949f9073c", "d6cae718867240b50f1d96edc7c3c7427657a3da8c88f3571b9b4ce57d13728c"],
    "lib/features/settings/overview/sections/dns_options_page.dart" => ["d5e5feb01d7827768353e53543afe03e8556803e8dbc34c885b2d6609c112a5c", "9449be02318e2afd987e0b0e0e275e1162d93acc86aa4131979b3951fd60f883"],
    "lib/features/settings/overview/sections/general_page.dart" => ["a24ac6ff890ab09c1ed9fb7b66a8dddf04b007e5a35969797cb330f763065d78", "be55bda6f775f55e2d7d997d24eaf93f77636c4911b71fba15288d9d5c931bf7"],
    "lib/features/settings/overview/sections/inbound_options_page.dart" => ["0cc0762d605d2088e911cac2c912017cd1ea23e18dca52ca43aae4e505fab05d", "42b0063d77902578758e6679fb8f7318b9846994bbb5091a3056eba062aa067d"],
    "lib/features/settings/overview/sections/route_options_page.dart" => ["6e59bdfda2ce645e9db57a019f65a0756d13be62e928bc58797e9e7a7d288e5e", "21d21df975c71a75a95a49441e939f089def0ef2cc0f0f0eee83e4e566b9339d"],
    "lib/features/settings/overview/sections/tls_tricks_page.dart" => ["34c2b98a5f6674aadc7d9b9951effd47bdae11f8d24dcd34fbd5a2664f774078", "2e88a4f024c5be4afd8d34a767473d06a17f023c5b9ed484965807167d3dd7a3"],
    "lib/features/settings/overview/sections/warp_options_page.dart" => ["94aa45b30e3ace4c135fa2b511882e7d81b1ec82bd349f5cb9fdbeb92cde725a", "f67421feb74daac3414c9668ca2182a763891ced171750616dc03ad4a5eafc8d"],
    "lib/features/settings/overview/settings_page.dart" => ["590024697af84b7275515a1a581145c785329c082559637a71d924e68a8dc5b2", "7b8ad5ccc13557eafb722138103fc2eceea55252251d42cdcfff5ce337952cbd"],
    "lib/features/settings/widget/preference_tile.dart" => ["998751a82aa87f58d2afb14d8c37b8f48fc2ff6a90abf2ccc9d6ce63b98f3c29", "6a926dba25230fe2c848b8eefb2ba18ddf5146d6105dab9c1967f7b4b72714ac"],
    "pubspec.yaml" => ["c78ca81b70b7ffc6bf7aebb3a789f865ca69ea369b6d195d504ac7d7169aa1a5", "bb87d6dc780627d07b85303d2d8343629d602fc65c7c9125179040d268a39b3e"],
    "scripts/blizzard_visual_acceptance.py" => ["ba61cf2bec85095106371a921f4e787f1d28c3e04c71a1fb54bda58ee5f3ce6d", "1c29c505341cddc68c87162276a21bffbb1faa722c04422e5dbcd7e449560f95"],
  }.freeze
  AURORA_NEW_SHA256 = {
    "assets/shaders/blizzard_aurora.frag" => "791f6f1c746fedb7df411df9bcc70516ef5e5ff46a4c5ade9c1a55c81026fa47",
    "ios/Runner/BlizzardSystemSymbols.swift" => "6ec1b767c1e542183e9cc9528b5ed09270d066ce9d981f35b24b836dc437fc28",
    "lib/core/widget/blizzard/blizzard_native_connection_control.dart" => "79febb26929447e76ffbf84ecf945fae6641a32fc5c6b4480f3fd6319f44ad0d",
    "lib/core/widget/blizzard/blizzard_system_symbol.dart" => "ed2676773f1dbbcc39d7a33cd8f3171cafb57bf6a7c817f95b412607e62c99b7",
    "lib/core/widget/blizzard/blizzard_system_symbol_map.dart" => "1288ef4b310fff4ff0cb13f158f6704e735b2fd2706f7d521ccf3a436572f155",
  }.freeze
  UI_FILES = %w[
    lib/core/theme/app_theme.dart lib/core/theme/theme_extensions.dart
    lib/core/router/adaptive_layout/my_adaptive_layout.dart
    lib/features/home/widget/home_page.dart lib/features/home/widget/connection_button.dart
    lib/features/profile/widget/profile_tile.dart lib/features/proxy/widget/proxy_tile.dart
    lib/features/proxy/active/active_proxy_card.dart lib/features/proxy/active/active_proxy_delay_indicator.dart
    lib/features/settings/widget/preference_tile.dart lib/features/common/general_pref_tiles.dart
    lib/features/profile/add/add_profile_modal.dart lib/features/profile/overview/profiles_modal.dart
    lib/core/router/bottom_sheets/widgets/quick_settings_modal.dart
    lib/features/profile/details/profile_details_page.dart lib/features/profile/details/json_editor.dart
    lib/features/proxy/overview/proxies_overview_page.dart lib/features/common/qr_code_scanner_screen.dart
    lib/features/common/qr_code_dialog.dart
    lib/features/log/overview/logs_page.dart lib/features/about/widget/about_page.dart
    lib/features/intro/widget/intro_page.dart
  ].freeze
  UI_PREFIXES = %w[lib/core/router/dialog/widgets/ lib/features/settings/overview/].freeze
  NEW_UI_PREFIXES = %w[lib/core/widget/blizzard/].freeze
  NEW_UI_FILES = %w[lib/core/theme/blizzard_tokens.dart lib/core/theme/blizzard_theme.dart lib/core/router/adaptive_layout/blizzard_dock.dart].freeze
  NATIVE_GLASS_FILE = "ios/Runner/BlizzardNativeGlass.swift"
  NATIVE_GLASS_SHA256 = "23ef7a0c8f086cb0b4a116e72b16a5d676a1ea489d427c3931ab58481b307e93"
  NATIVE_GLASS_HOST_SHA256 = {
    "ios/Runner/AppDelegate.swift" => [
      "cd1c79e1b3320c6e6fd01d08df8ebd7d310c55adbd548a5a3397d7454b88bf04",
      "ca0e72cb2f3c87edbb25f49b0701b322ff968b74775d6622eb3a4a5a5d4be895",
    ],
    "ios/Runner.xcodeproj/project.pbxproj" => [
      "11423d2e5f5c60edf42587fc9797d6c3948437d2acd47fbaa7959a54b7928f69",
      "221630aace49cfa805c367e231bed8fc86318a17060e4f53efd8398f9c3edf51",
    ],
    "ios/RunnerTests/RunnerTests.swift" => [
      "5e8f4908dacea6f29b2a790e4d38bf5fded69096063f9a27a2f21584d62b30c0",
      "8463f988b9823e3414cf7227f66068eba654bee63d2ec00ae95eca0bc00eace9",
    ],
  }.freeze
  # Exact build-21 source additions carried forward from the trusted release
  # line. These paths are protected from incidental runtime drift just like
  # the older diagnostics fingerprints below.
  RELEASE_SOURCE_SHA256 = {
    ".github/workflows/build.yml" => ["a2eb32f3a0bf0d30f3b31a51ea92a0b32d4fa9973b726eee383caf15656f69e6", "d49a02606bfc045fae46448e8a7dcb514ab78fd51fca979f95546453cbde559d"],
    ".github/workflows/ci.yml" => ["6bcc935cb7841475f50748cd5d8b5be391af3a347857fbfa08920e6bd963f80b", "8f606970df6b5abb03b1b25b1253d15e4d15c66497994bb68220703b35479606"],
    ".github/workflows/ios-baseline.yml" => ["8ff1f9100e5d6d19747c251b23afc8e931082151c38a34960671da86f7c276d0", "85a85c2c223ed4e062a6b19709fc519d63ea3cfca9476cbdbb02b6f7af921054"],
    "assets/translations/en.i18n.json" => ["d1bdfe06b016b0e72828f4a5c980d8e1ae4146983ddd3d7630a1861bfd448acc", "c8620bce25da968f9af9d6ee5c2433487556032a754638331673b35c6e482dfa"],
    "assets/translations/ru.i18n.json" => ["218e2472e8eeca970a0ff160e612e87904f09cc8f4fba7ca4f351df47a0c35c5", "214b34c544c0135d90a252b36b525a15ebcabe654b28861a6ebf38ff7fcba1c6"],
    "ios/Runner/Handlers/StatusEventHandler.swift" => ["7dc456b95a10a459017a957a2146c0df3581a6df790d57b4dc75c9d041b3816d", "8910e6c427a204102d8261cc2594d9a293084e4c44c32f2c765e41637ef65655"],
    "ios/Runner/Info.plist" => ["3b43eb43ba3f09383810c8d231a8e5c0b67cd8f5bb19d23053e30289ee850b7d", "e470873245ee919499c8b57d4ff6b46014467ad4a8009056c0347158a3e86c2e"],
    "ios/Runner/VPN/VPNManager.swift" => ["9f207ded470097e274e1cdb4d238fe1734d57ac4ae452e9844de0a89dfa86dff", "9b69434490e99cb68c93d55c1d3ffcedb2da08f5007a8de94cd390651789aa1d"],
    "lib/core/analytics/analytics_controller.dart" => ["2a84ad1b04bd809c2641605c070c9c2baae0bcb67c896e02604d8c35d9d02498", "c7e09f00d20b504d350c890850231bd2e44ec6a5ad0c81ebbc1d696ec51cad6a"],
    "lib/core/model/app_info_entity.dart" => ["89e024c6f3041e18540e8a78cfec49529020d36ba70cd7b27b45f70416a999bb", "7207abcabc9dc7e676a9524f5f08985a28350d0b195fbb92e36d6d04611fbd5b"],
    "lib/core/model/constants.dart" => ["cb46da835e646341f79f41f53da2b1c665cb159ef10c61dbea5d72f55382b369", "da33cdb4b668428371bf8749d718d132571b175d79324e98b1f3fad9ef6895d8"],
    "lib/core/model/environment.dart" => ["5c932e3d18573ca445ca1acf6dd2c7179cb9b971d1710d9003afaa6382fc63b5", "7b8ce7a0f3ac9b3d820f64a39e3984db4ff791766d53c6b72d4aaaa12b384260"],
    "lib/features/connection/data/connection_repository.dart" => ["4317bad18edde90be73228303e8cbf9a779c6b8a80c53d0539d296b1f9602d4c", "b8247270dd21d92df1fefa23ea856c3ca7d4529e8ecc8fba08884aedbc76ccfb"],
    "lib/hiddifycore/core_interface/core_interface.dart" => ["0576c4eb9a35f0d8302c13f193da05079c9ba7b311026c7b328b5707889b4280", "660445286fc44d4ba38256c5dee154f5f09c188368601a77f5e7d7531db801ff"],
    "lib/hiddifycore/core_interface/core_interface_mobile.dart" => ["e0672d710ce7341cde00e6543458e2ed6ab5a6948c389ff45dcc7788c19baf26", "76460b9358ab9099288d162199ae97544efe9689dc2f080bb3eda0973a03c6b0"],
    "lib/hiddifycore/hiddify_core_service.dart" => ["d55abf280b332358e89a6ee932929616e711b7c923ee60caf08413de9b781ac3", "b6b1be09d437eab148d494dfb5e784896493f1d4fc71ea1e64ce699cab06aee4"],
  }.freeze
  RELEASE_NEW_SHA256 = {
    ".github/workflows/baseline-telemetry.yml" => "afd597ef89b7cdfe37b7f8a951787a29b80c776560d26d66e0f20efca3a06128",
    "lib/core/analytics/telemetry_delivery_provider.dart" => "b81e932c072452710203e57cb92cd76e285d07113f3f45248eb1f2d15218b83e",
    "lib/core/observability/better_stack_log_printer.dart" => "8955fd3587c047dec4e23af21feedcb18fda4100910b854c06e4a2cc69089162",
    "lib/core/observability/telemetry_budget.dart" => "b5251021276928c3927e5026d60f0e22cadfb07aa8aae42f4771c38287676777",
    "lib/core/observability/telemetry_delivery_status.dart" => "c774f10e3f011fd98987ae2278cb0647d212577dd4d0c018fb1c1661b6602af1",
    "lib/features/diagnostics/remote_diagnostic_subscription.dart" => "d9d386c45564403e69be4a43163388f3189caab4da5b86518bf6c99bc23a3e5c",
    "lib/features/diagnostics/remote_ios_ping_subscription.dart" => "3462df29c7779f0d3623442f4a9d3e1bae5d33ecbc797c5b68b9580a765649eb",
    "lib/features/diagnostics/telemetry_delivery_labels.dart" => "c86eb93a4f04e500bb9846b5d2117e5344d62e9c0a3ab4a2dd3623d34ec7e989",
  }.freeze
  DEV_ADDITIONS = %w[flutter_driver fuchsia_remote_debug_protocol integration_test sync_http webdriver].freeze
  PROFILE_DETAILS_NOTIFIER = "lib/features/profile/details/profile_details_notifier.dart"
  APPROVED_RAW_LOG_LINE = "      loggy.info(profContent);\n"
  TRUSTED_PARSE_ERROR_LINE = "      loggy.error('Error parsing profile-content JSON', e, st);\n"
  APPROVED_PARSE_ERROR_LINE =
    "      loggy.error('Error parsing profile-content JSON (${e.runtimeType})', null, st);\n"

  # Exact source fingerprints for the independently reviewed diagnostics batch.
  # Keep this list narrow; the VPN repository, notifier, core and bridge remain protected.
  DIAGNOSTIC_EXISTING_FILES = %w[
    assets/translations/en.i18n.json assets/translations/ru.i18n.json
    ios/HiddifyPacketTunnel/Logger.swift
    ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift
    ios/Runner/VPN/VPNManager.swift
    lib/core/analytics/analytics_controller.dart lib/core/analytics/analytics_filter.dart
    lib/core/logger/logger_controller.dart
    lib/features/connection/data/connection_data_providers.dart
    lib/features/log/overview/logs_page.dart
  ].freeze
  DIAGNOSTIC_SOURCE_SHA256 = {
    "assets/translations/en.i18n.json" => ["d1bdfe06b016b0e72828f4a5c980d8e1ae4146983ddd3d7630a1861bfd448acc", "c8620bce25da968f9af9d6ee5c2433487556032a754638331673b35c6e482dfa"],
    "assets/translations/ru.i18n.json" => ["218e2472e8eeca970a0ff160e612e87904f09cc8f4fba7ca4f351df47a0c35c5", "214b34c544c0135d90a252b36b525a15ebcabe654b28861a6ebf38ff7fcba1c6"],
    "ios/HiddifyPacketTunnel/Logger.swift" => ["197a03eb1212f113e934b913525a6d329e2ec5538b97bf71a3296571c07499a7", "dd25284df008b05268740bbd720969eb337982eece068819002a20b8a58a8964"],
    "ios/HiddifyPacketTunnel/SingBox/ExtensionProvider.swift" => ["5d34a57ef76d904bece6462519d340c7ff217b57ff3237bb82e69d82b1a28848", "8876aae20b2e98c0cef2abf66b82080461f770e5b007d0eba9ff547e9880f4aa"],
    "ios/Runner/VPN/VPNManager.swift" => ["9f207ded470097e274e1cdb4d238fe1734d57ac4ae452e9844de0a89dfa86dff", "9b69434490e99cb68c93d55c1d3ffcedb2da08f5007a8de94cd390651789aa1d"],
    "lib/core/analytics/analytics_controller.dart" => ["2a84ad1b04bd809c2641605c070c9c2baae0bcb67c896e02604d8c35d9d02498", "c7e09f00d20b504d350c890850231bd2e44ec6a5ad0c81ebbc1d696ec51cad6a"],
    "lib/core/analytics/analytics_filter.dart" => ["3395f98c9c53da22017b48b657a29d725c3cbbd7ef6cc205a3506332ab5c4e59", "537bd175fa6172c7ac621b1c150f81f2fe2bfa388f205f42c954c43f1f89090a"],
    "lib/core/logger/logger_controller.dart" => ["d78b51210488b4d967c2aee9efbc42d1e6f50b325dc42319d535569c17902e5c", "887355613fb31ae023c1582fc8c7b9e98f0424da1567a6465831514991f900b8"],
    "lib/features/connection/data/connection_data_providers.dart" => ["08624ce007644a397effdeaa42da18d4381195c0feda55e4fe7d7faa2587483d", "aea92301c08f51c603a3917f17c95c0d42b7c54936757545936df5e3ab31abe3"],
    "lib/features/log/overview/logs_page.dart" => ["492d35c4ea6cf24f86dc1b1114ecbdb2713ed6657b8c8d6053d077e6bb2be66b", "8683fc35beb7940ddbef4423166b0440e79bef23f697b8d247f98b6fd9cabee5"],
  }.freeze

  DIAGNOSTIC_NEW_FILES = %w[
    lib/core/logger/safe_log_record.dart
    lib/features/diagnostics/safe_diagnostic_event.dart
    lib/features/diagnostics/safe_diagnostic_journal.dart
    lib/features/diagnostics/home_presentation_snapshot.dart
    lib/features/diagnostics/home_presentation_providers.dart
    lib/features/diagnostics/home_presentation_probe.dart
    lib/features/diagnostics/observed_connection_repository.dart
    lib/features/diagnostics/diagnostic_providers.dart
    lib/features/diagnostics/safe_diagnostics_page.dart
    lib/features/diagnostics/ios_ping_trace.dart
  ].freeze
  DIAGNOSTIC_NEW_SHA256 = {
    "lib/core/logger/safe_log_record.dart" => "57137aee501d92bd54129bc3ce34814efabb2a96f6dd5deab5c48040019b183a",
    "lib/features/diagnostics/safe_diagnostic_event.dart" => "867a3fc3c57f729b0de11787f130e18ed2cabc66cbfd36a3344a3a9f1e7a66a6",
    "lib/features/diagnostics/safe_diagnostic_journal.dart" => "b84f1dca5f57aee57a7cc2658306038909a48c7eb2b71a00a5c427dcd346f364",
    "lib/features/diagnostics/home_presentation_snapshot.dart" => "2e816bf1093b990599747c3860138d489f1a520667c0bbb093ca930289913ded",
    "lib/features/diagnostics/home_presentation_providers.dart" => "43cb56211b4055a2ebf41abb2097d754be3f589d56b377f06c3450b6f3433602",
    "lib/features/diagnostics/home_presentation_probe.dart" => "f51164d3f3433f0ff3c9ebffdc82de291cc38382f93e7200c28f938bec5bc728",
    "lib/features/diagnostics/observed_connection_repository.dart" => "8bd1bdcc05099863f93641b08a16a21e3d3b209f0736ea1cb9df35fc922e8cb1",
    "lib/features/diagnostics/diagnostic_providers.dart" => "ccbd9164f42ef63602b640de0ce0c5e35f81bf2f3dcaafca07351ccd16a2be75",
    "lib/features/diagnostics/safe_diagnostics_page.dart" => "9d46c9744651164f99572c80dbe8a932dab89f73d05c3b02c5058d2904151067",
    "lib/features/diagnostics/ios_ping_trace.dart" => "7b0818f4d26fdddd5c59dcafc9decb6f90e54244edf8722ba96a058b4a0b9292",
  }.freeze

  # Exact reviewed iOS active-proxy measurement sources; no directory allowance.
  IOS_MEASUREMENT_SOURCE_SHA256 = {
    "lib/features/proxy/active/active_proxy_notifier.dart" => ["d1c13a0efac2e778de8e7a3d74bdfb97518aeba4cf1ed036c70051d44f9d1529", "9a6b08f9ca02a6c997f445a4309a7de13190f9508915870bcb1f0206c4807290"],
    "lib/hiddifycore/hiddify_core_service.dart" => ["d55abf280b332358e89a6ee932929616e711b7c923ee60caf08413de9b781ac3", "b6b1be09d437eab148d494dfb5e784896493f1d4fc71ea1e64ce699cab06aee4"],
  }.freeze
  IOS_MEASUREMENT_NEW_SHA256 = {
    "lib/features/proxy/active/ios_active_proxy_measurement.dart" => "71d35a6282bb85980bfc91f9a3c128af028a10d20e82f0f2a6d7ee1cd9b4ce1e",
    "lib/features/proxy/active/ios_active_proxy_measurement_providers.dart" => "2fd3bfbe42f72594054ba06e3922acdaad08cf352712f6d41f393fc617a35e50",
    "lib/features/proxy/active/ios_active_proxy_delay_indicator.dart" => "b68b3d61ad632bbe1d2b46ce5ecbe0094ee4b693107fd36a0b4da03027bb7d91",
  }.freeze

  # Exact iOS startup recovery sources; no lifecycle/core directory allowance.
  IOS_STARTUP_SOURCE_SHA256 = {
    "lib/bootstrap.dart" => ["d035a1bec3386d5f1320cfc7ef7eec9f260621f5d2868706670efe71fcfb24e9", "c7c92337c2f9ece8f392ae851df0f15f8269a8c8367b0a4fafaa7ff9a2901fda"],
    "lib/features/app/widget/app.dart" => ["f3907fa99dcbe37c300f9c1c856d1ae18943754019193eda1a01dc6df3532390", "c3923577ee27bfa100cb2f1a3fdf687f611b988186eabc0dd2f758675c093b67"],
    "lib/hiddifycore/core_interface/core_interface_mobile.dart" => ["e0672d710ce7341cde00e6543458e2ed6ab5a6948c389ff45dcc7788c19baf26", "76460b9358ab9099288d162199ae97544efe9689dc2f080bb3eda0973a03c6b0"],
    "ios/Runner/Handlers/MethodHandler.swift" => ["288bcd062d01bd336e97346a0b160e5e45f772956380c1c7392b04a6771e0006", "0b31cee80b348c6e3cbf31bf0abc9187d58d0665ccbbde81758fd03813ae1195"],
  }.freeze
  IOS_STARTUP_NEW_SHA256 = {
    "lib/features/app/startup/ios_startup_gate.dart" => "9073defe1819cc9801ea3e3a5495947970c40ea60df175a664206c715a6a87db",
  }.freeze

  def approved_ios_startup_change?(path, trusted_source, current_source)
    fingerprints = IOS_STARTUP_SOURCE_SHA256[path]
    (fingerprints &&
      Digest::SHA256.hexdigest(trusted_source) == fingerprints.fetch(0) &&
      Digest::SHA256.hexdigest(current_source) == fingerprints.fetch(1)) ||
      approved_pinned_baseline_change?(path, trusted_source, current_source) ||
      approved_aurora_change_from_old?(path, trusted_source, current_source) ||
      approved_current_patch_change_from_baseline?(path, trusted_source, current_source) ||
      approved_luma_change_from_baseline?(path, trusted_source, current_source)
  end

  def approved_native_glass_host_change?(path, trusted_source, current_source)
    fingerprints = NATIVE_GLASS_HOST_SHA256[path]
    (fingerprints &&
      Digest::SHA256.hexdigest(trusted_source) == fingerprints.fetch(0) &&
      Digest::SHA256.hexdigest(current_source) == fingerprints.fetch(1)) ||
      approved_pinned_baseline_change?(path, trusted_source, current_source) ||
      approved_aurora_change_from_old?(path, trusted_source, current_source) ||
      approved_current_patch_change_from_baseline?(path, trusted_source, current_source) ||
      approved_luma_change_from_baseline?(path, trusted_source, current_source)
  end

  def approved_release_change?(path, trusted_source, current_source)
    fingerprints = RELEASE_SOURCE_SHA256[path]
    (fingerprints &&
      Digest::SHA256.hexdigest(trusted_source) == fingerprints.fetch(0) &&
      Digest::SHA256.hexdigest(current_source) == fingerprints.fetch(1)) ||
      approved_pinned_baseline_change?(path, trusted_source, current_source) ||
      approved_aurora_change_from_old?(path, trusted_source, current_source) ||
      approved_current_patch_change_from_baseline?(path, trusted_source, current_source) ||
      approved_luma_change_from_baseline?(path, trusted_source, current_source)
  end

  def git_blob(commit, path)
    output, _, status = Open3.capture3("git", "-C", ROOT, "show", "#{commit}:#{path}")
    status.success? ? output : nil
  end

  def approved_pinned_baseline_change?(path, trusted_source, current_source)
    original = git_blob(BASELINE, path)
    pinned = git_blob(AURORA_BASELINE, path)
    original && pinned &&
      Digest::SHA256.hexdigest(trusted_source) == Digest::SHA256.hexdigest(original) &&
      Digest::SHA256.hexdigest(current_source) == Digest::SHA256.hexdigest(pinned)
  end

  def approved_pinned_baseline_addition?(path, current_source)
    return false if git_blob(BASELINE, path)

    pinned = git_blob(AURORA_BASELINE, path)
    pinned && Digest::SHA256.hexdigest(current_source) == Digest::SHA256.hexdigest(pinned)
  end

  def approved_exact_change?(fingerprints, path, trusted_source, current_source)
    expected = fingerprints[path]
    expected &&
      Digest::SHA256.hexdigest(trusted_source) == expected.fetch(0) &&
      Digest::SHA256.hexdigest(current_source) == expected.fetch(1)
  end

  def approved_exact_addition?(fingerprints, path, current_source)
    expected = fingerprints[path]
    expected && Digest::SHA256.hexdigest(current_source) == expected
  end

  def approved_current_patch_change?(path, current_source)
    trusted = git_blob(CURRENT_PATCH_BASE, path)
    trusted && approved_exact_change?(CURRENT_PATCH_SOURCE_SHA256, path, trusted, current_source)
  end

  def approved_current_patch_change_from_baseline?(path, baseline_source, current_source)
    original = git_blob(BASELINE, path)
    original &&
      Digest::SHA256.hexdigest(baseline_source) == Digest::SHA256.hexdigest(original) &&
      approved_current_patch_change?(path, current_source)
  end

  def approved_current_patch_addition?(path, current_source)
    git_blob(CURRENT_PATCH_BASE, path).nil? &&
      approved_exact_addition?(CURRENT_PATCH_NEW_SHA256, path, current_source)
  end

  def approved_luma_change?(path, current_source)
    trusted = git_blob(LUMA_BASELINE, path)
    trusted && approved_exact_change?(LUMA_SOURCE_SHA256, path, trusted, current_source)
  end

  def approved_luma_snapshot?(path, current_source)
    trusted = git_blob(LUMA_BASELINE, path)
    (trusted && Digest::SHA256.hexdigest(current_source) == Digest::SHA256.hexdigest(trusted)) ||
      approved_luma_change?(path, current_source)
  end

  def approved_luma_change_from_baseline?(path, baseline_source, current_source)
    original = git_blob(BASELINE, path)
    original &&
      Digest::SHA256.hexdigest(baseline_source) == Digest::SHA256.hexdigest(original) &&
      approved_luma_snapshot?(path, current_source)
  end

  def approved_luma_addition?(path, current_source)
    git_blob(LUMA_BASELINE, path).nil? &&
      approved_exact_addition?(LUMA_NEW_SHA256, path, current_source)
  end

  def approved_aurora_change?(path, current_source)
    trusted = git_blob(AURORA_BASELINE, path)
    trusted && approved_exact_change?(AURORA_CHANGE_SHA256, path, trusted, current_source)
  end

  def approved_aurora_change_from_old?(path, old_source, current_source)
    original = git_blob(BASELINE, path)
    original &&
      Digest::SHA256.hexdigest(old_source) == Digest::SHA256.hexdigest(original) &&
      approved_aurora_change?(path, current_source)
  end

  def approved_aurora_addition?(path, current_source)
    approved_exact_addition?(AURORA_NEW_SHA256, path, current_source) ||
      approved_current_patch_change?(path, current_source) ||
      approved_current_patch_addition?(path, current_source) ||
      approved_luma_change?(path, current_source) ||
      approved_luma_addition?(path, current_source)
  end

  def aurora_runtime_path?(path)
    !path.start_with?("docs/", "test/", "integration_test/")
  end

  def aurora_runtime_delta_paths
    git("diff", "--name-only", "--diff-filter=ACMR", AURORA_BASELINE, CURRENT_PATCH_BASE, "--").lines.map(&:strip)
      .select { |path| aurora_runtime_path?(path) }.sort
  end

  def aurora_runtime_deletions
    git("diff", "--name-only", "--diff-filter=D", AURORA_BASELINE, CURRENT_PATCH_BASE, "--").lines.map(&:strip)
      .select { |path| aurora_runtime_path?(path) }
  end

  def current_patch_runtime_delta_paths
    git("diff", "--name-only", "--diff-filter=ACMR", CURRENT_PATCH_BASE, CURRENT_PATCH_SNAPSHOT, "--").lines.map(&:strip)
      .select { |path| aurora_runtime_path?(path) }.sort
  end

  def current_patch_runtime_deletions
    git("diff", "--name-only", "--diff-filter=D", CURRENT_PATCH_BASE, CURRENT_PATCH_SNAPSHOT, "--").lines.map(&:strip)
      .select { |path| aurora_runtime_path?(path) }
  end

  def luma_production_path?(path)
    !path.start_with?("docs/", "test/", "integration_test/", "test_driver/", "tool/")
  end

  def luma_production_delta_paths
    tracked = git("diff", "--name-only", "--diff-filter=ACMR", LUMA_BASELINE, "--").lines.map(&:strip)
    untracked = git("ls-files", "--others", "--exclude-standard").lines.map(&:strip)
    (tracked + untracked).uniq.select { |path| luma_production_path?(path) }.sort
  end

  def luma_production_deletions
    git("diff", "--name-only", "--diff-filter=D", LUMA_BASELINE, "--").lines.map(&:strip)
      .select { |path| luma_production_path?(path) }
  end

  def compiled_swift_source?(project_source, filename)
    name = Regexp.escape(filename)
    build_files = project_source.scan(
      /^\s*([A-F0-9]+) \/\* #{name} in Sources \*\/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]+) \/\* #{name} \*\/; \};\s*$/,
    )
    return false unless build_files.one?

    build_id, file_id = build_files.first
    file_reference = /^\s*#{Regexp.escape(file_id)} \/\* #{name} \*\/ = \{isa = PBXFileReference;.*?path = #{name};.*?\};\s*$/
    group_membership = /^\s*#{Regexp.escape(file_id)} \/\* #{name} \*\/,\s*$/
    source_membership = /^\s*#{Regexp.escape(build_id)} \/\* #{name} in Sources \*\/,\s*$/
    project_source.scan(file_reference).one? &&
      project_source.scan(group_membership).one? &&
      project_source.scan(source_membership).one?
  end

  def test_exact_incremental_change_guard_rejects_unreviewed_bytes_and_paths
    trusted = "trusted source\n"
    current = "approved source\n"
    fingerprints = {
      "ios/Runner/Approved.swift" => [
        Digest::SHA256.hexdigest(trusted),
        Digest::SHA256.hexdigest(current),
      ],
    }

    assert approved_exact_change?(fingerprints, "ios/Runner/Approved.swift", trusted, current)
    refute approved_exact_change?(fingerprints, "ios/Runner/Approved.swift", trusted + " ", current)
    refute approved_exact_change?(fingerprints, "ios/Runner/Approved.swift", trusted, current + " ")
    refute approved_exact_change?(fingerprints, "ios/Runner/Adjacent.swift", trusted, current)
  end

  def test_exact_incremental_addition_guard_rejects_unreviewed_bytes_and_paths
    current = "approved source\n"
    fingerprints = {
      "assets/shaders/approved.frag" => Digest::SHA256.hexdigest(current),
    }

    assert approved_exact_addition?(fingerprints, "assets/shaders/approved.frag", current)
    refute approved_exact_addition?(fingerprints, "assets/shaders/approved.frag", current + " ")
    refute approved_exact_addition?(fingerprints, "assets/shaders/adjacent.frag", current)
  end

  def test_luma_existing_file_requires_the_exact_reviewed_transition
    path = "assets/translations/en.i18n.json"
    trusted = git_blob(LUMA_BASELINE, path)
    current = File.binread(File.join(ROOT, path))

    assert approved_release_change?(path, git_blob(BASELINE, path), current)
    assert approved_exact_change?(LUMA_SOURCE_SHA256, path, trusted, current)
    refute approved_exact_change?(LUMA_SOURCE_SHA256, path, trusted + " ", current)
    refute approved_exact_change?(LUMA_SOURCE_SHA256, path, trusted, current + " ")
    refute approved_exact_change?(LUMA_SOURCE_SHA256, "assets/translations/adjacent.i18n.json", trusted, current)
  end

  def test_luma_existing_files_match_exact_reviewed_fingerprints
    LUMA_SOURCE_SHA256.each do |path, expected|
      trusted = git_blob(LUMA_BASELINE, path)
      current = File.binread(File.join(ROOT, path))
      refute_nil trusted, path
      assert_equal expected.fetch(0), Digest::SHA256.hexdigest(trusted), path
      assert approved_luma_change?(path, current), path
      refute approved_luma_change?(path, current + " "), path
      refute approved_luma_change?("#{path}.unreviewed", current), path
    end
  end

  def test_luma_new_files_reject_unreviewed_bytes_and_paths
    LUMA_NEW_SHA256.each_key do |path|
      current = File.binread(File.join(ROOT, path))
      assert allowed_addition?(path), path
      assert approved_exact_addition?(LUMA_NEW_SHA256, path, current), path
      refute approved_exact_addition?(LUMA_NEW_SHA256, path, current + " "), path
      refute approved_exact_addition?(LUMA_NEW_SHA256, "#{path}.unreviewed", current), path
    end
    refute allowed_addition?("lib/core/widget/blizzard/blizzard_toolbar_extra.dart")
  end

  def test_luma_production_delta_is_exactly_the_reviewed_file_set
    assert_empty luma_production_deletions
    assert_equal (LUMA_SOURCE_SHA256.keys + LUMA_NEW_SHA256.keys).sort, luma_production_delta_paths
    assert_empty LUMA_SOURCE_SHA256.keys & LUMA_NEW_SHA256.keys
    assert_includes LUMA_SOURCE_SHA256, "lib/features/diagnostics/safe_diagnostics_page.dart"
    %w[docs/ integration_test/ test/ test_driver/ tool/].each do |prefix|
      refute luma_production_path?("#{prefix}unreviewed.dart"), prefix
    end
  end

  def test_exact_pinned_baseline_transition_rejects_unreviewed_bytes_and_paths
    path = "lib/core/analytics/analytics_controller.dart"
    trusted = git_blob(BASELINE, path)
    pinned = git_blob(AURORA_BASELINE, path)
    refute_nil trusted
    refute_nil pinned

    assert approved_pinned_baseline_change?(path, trusted, pinned)
    refute approved_pinned_baseline_change?(path, trusted + " ", pinned)
    refute approved_pinned_baseline_change?(path, trusted, pinned + " ")
    refute approved_pinned_baseline_change?("#{path}.unreviewed", trusted, pinned)
  end

  def test_exact_pinned_baseline_addition_rejects_unreviewed_bytes_and_paths
    path = "lib/core/observability/telemetry_transport_attempt.dart"
    pinned = git_blob(AURORA_BASELINE, path)
    refute_nil pinned

    assert approved_pinned_baseline_addition?(path, pinned)
    refute approved_pinned_baseline_addition?(path, pinned + " ")
    refute approved_pinned_baseline_addition?("#{path}.unreviewed", pinned)
  end

  def test_system_symbols_has_exactly_one_runner_compile_membership
    path = "ios/Runner.xcodeproj/project.pbxproj"
    before = git_blob(AURORA_BASELINE, path)
    after = File.binread(File.join(ROOT, path))

    refute compiled_swift_source?(before, "BlizzardSystemSymbols.swift")
    assert compiled_swift_source?(after, "BlizzardSystemSymbols.swift")
    refute compiled_swift_source?(after.sub("BlizzardSystemSymbols.swift in Sources */,", "BlizzardSystemSymbols.swift */,"), "BlizzardSystemSymbols.swift")
    refute compiled_swift_source?(after, "Unreviewed.swift")
  end

  def test_aurora_runtime_delta_is_exactly_the_reviewed_file_set
    assert_empty aurora_runtime_deletions
    expected = (AURORA_CHANGE_SHA256.keys + AURORA_NEW_SHA256.keys)
      .uniq.select { |path| aurora_runtime_path?(path) }.sort
    assert_equal expected, aurora_runtime_delta_paths
    assert_empty AURORA_CHANGE_SHA256.keys & AURORA_NEW_SHA256.keys
  end

  def test_current_patch_runtime_delta_is_exactly_the_reviewed_file_set
    assert_empty current_patch_runtime_deletions
    expected = (CURRENT_PATCH_SOURCE_SHA256.keys + CURRENT_PATCH_NEW_SHA256.keys)
      .uniq.select { |path| aurora_runtime_path?(path) }.sort
    assert_equal expected, current_patch_runtime_delta_paths
    assert_empty CURRENT_PATCH_SOURCE_SHA256.keys & CURRENT_PATCH_NEW_SHA256.keys
  end

  def test_current_patch_existing_files_match_exact_reviewed_fingerprints
    CURRENT_PATCH_SOURCE_SHA256.each do |path, expected|
      trusted = git_blob(CURRENT_PATCH_BASE, path)
      current = git_blob(CURRENT_PATCH_SNAPSHOT, path)
      refute_nil trusted, path
      refute_nil current, path
      assert_equal expected.fetch(0), Digest::SHA256.hexdigest(trusted), path
      assert approved_current_patch_change?(path, current), path
      refute approved_current_patch_change?(path, current + " "), path
      refute approved_current_patch_change?("#{path}.unreviewed", current), path
    end
  end

  def test_current_patch_new_files_match_exact_reviewed_fingerprints
    CURRENT_PATCH_NEW_SHA256.each do |path, expected|
      assert_nil git_blob(CURRENT_PATCH_BASE, path), path
      current = git_blob(CURRENT_PATCH_SNAPSHOT, path)
      refute_nil current, path
      assert_equal expected, Digest::SHA256.hexdigest(current), path
      assert approved_current_patch_addition?(path, current), path
      refute approved_current_patch_addition?(path, current + " "), path
      refute approved_current_patch_addition?("#{path}.unreviewed", current), path
    end
  end

  def test_aurora_existing_files_match_exact_pinned_transition_fingerprints
    AURORA_CHANGE_SHA256.each do |path, expected|
      trusted = git_blob(AURORA_BASELINE, path)
      current = git_blob(CURRENT_PATCH_BASE, path)
      refute_nil trusted, path
      refute_nil current, path
      assert_equal expected.fetch(0), Digest::SHA256.hexdigest(trusted), path
      assert approved_aurora_change?(path, current), path
      refute approved_exact_change?(AURORA_CHANGE_SHA256, path, trusted + " ", current), path
      refute approved_exact_change?(AURORA_CHANGE_SHA256, path, trusted, current + " "), path
      refute approved_aurora_change?("#{path}.unreviewed", current), path
    end
  end

  def test_aurora_new_files_match_exact_fingerprints
    AURORA_NEW_SHA256.each_key do |path|
      assert_nil git_blob(AURORA_BASELINE, path), path
      current = git_blob(CURRENT_PATCH_BASE, path)
      refute_nil current, path
      assert approved_aurora_addition?(path, current), path
      refute approved_aurora_addition?(path, current + " "), path
      refute approved_aurora_addition?("#{path}.unreviewed", current), path
    end
  end

  def test_release_fingerprints_reject_unreviewed_bytes_and_paths
    RELEASE_SOURCE_SHA256.each do |path, _|
      trusted = git("show", "#{BASELINE}:#{path}")
      current = File.binread(File.join(ROOT, path))
      assert approved_release_change?(path, trusted, current), path
      refute approved_release_change?(path, trusted + " ", current), path
      refute approved_release_change?(path, trusted, current + " "), path
      refute approved_release_change?("#{path}.unreviewed", trusted, current), path
    end
  end

  def test_release_additions_match_reviewed_fingerprints
    RELEASE_NEW_SHA256.each do |path, expected|
      current = File.binread(File.join(ROOT, path))
      assert expected == Digest::SHA256.hexdigest(current) ||
        approved_pinned_baseline_addition?(path, current) ||
        approved_aurora_change?(path, current) ||
        approved_current_patch_change?(path, current) ||
        approved_luma_change?(path, current), path
      refute_equal expected, Digest::SHA256.hexdigest(File.binread(File.join(ROOT, path)) + " "), path
      refute RELEASE_NEW_SHA256.key?("#{path}.unreviewed"), path
    end
  end

  def test_native_glass_allowlist_accepts_only_the_frozen_host_changes
    NATIVE_GLASS_HOST_SHA256.each_key do |path|
      trusted = git("show", "#{BASELINE}:#{path}")
      current = File.binread(File.join(ROOT, path))
      assert approved_native_glass_host_change?(path, trusted, current), path
      refute approved_native_glass_host_change?(path, trusted + " ", current), path
      refute approved_native_glass_host_change?(path, trusted, current + " "), path
      refute approved_native_glass_host_change?("ios/Runner/Unapproved.swift", trusted, current), path
    end
    current = File.binread(File.join(ROOT, NATIVE_GLASS_FILE))
    assert NATIVE_GLASS_SHA256 == Digest::SHA256.hexdigest(current) ||
      approved_pinned_baseline_addition?(NATIVE_GLASS_FILE, current) ||
      approved_aurora_change?(NATIVE_GLASS_FILE, current) ||
      approved_current_patch_change?(NATIVE_GLASS_FILE, current) ||
      approved_luma_change?(NATIVE_GLASS_FILE, current)
    refute_equal NATIVE_GLASS_SHA256, Digest::SHA256.hexdigest(File.binread(File.join(ROOT, NATIVE_GLASS_FILE)) + " ")
  end

  def approved_ios_startup_addition?(path, current_source)
    fingerprint = IOS_STARTUP_NEW_SHA256[path]
    (fingerprint && Digest::SHA256.hexdigest(current_source) == fingerprint) ||
      approved_pinned_baseline_addition?(path, current_source) ||
      approved_aurora_change?(path, current_source) ||
      approved_aurora_addition?(path, current_source) ||
      approved_luma_change?(path, current_source) ||
      approved_luma_addition?(path, current_source)
  end

  def test_ios_startup_existing_fingerprints_reject_unreviewed_bytes_and_paths
    IOS_STARTUP_SOURCE_SHA256.each_key do |path|
      trusted = git("show", "#{BASELINE}:#{path}")
      current = File.binread(File.join(ROOT, path))
      assert approved_ios_startup_change?(path, trusted, current), path
      refute approved_ios_startup_change?(path, trusted + " ", current), path
      refute approved_ios_startup_change?(path, trusted, current + " "), path
      refute approved_ios_startup_change?("#{path}.unreviewed", trusted, current), path
      refute approved_ios_startup_change?("lib/hiddifycore/unreviewed.dart", trusted, current), path
    end
  end

  def test_ios_startup_new_fingerprints_reject_unreviewed_bytes_and_paths
    IOS_STARTUP_NEW_SHA256.each_key do |path|
      current = File.binread(File.join(ROOT, path))
      assert approved_ios_startup_addition?(path, current), path
      refute approved_ios_startup_addition?(path, current + " "), path
      refute approved_ios_startup_addition?("#{path}.unreviewed", current), path
      refute allowed_addition?("#{path}/extra.dart"), path
    end
    refute allowed_addition?("lib/features/app/startup/unreviewed.dart")
    refute allowed_addition?("lib/features/app/startup/ios_startup_gate_extra.dart")
    refute approved_ios_startup_addition?("lib/features/app/startup/unreviewed.dart", "")
  end

  def approved_ios_measurement_change?(path, trusted_source, current_source)
    fingerprints = IOS_MEASUREMENT_SOURCE_SHA256[path]
    (fingerprints &&
      Digest::SHA256.hexdigest(trusted_source) == fingerprints.fetch(0) &&
      Digest::SHA256.hexdigest(current_source) == fingerprints.fetch(1)) ||
      approved_pinned_baseline_change?(path, trusted_source, current_source) ||
      approved_aurora_change_from_old?(path, trusted_source, current_source) ||
      approved_current_patch_change_from_baseline?(path, trusted_source, current_source) ||
      approved_luma_change_from_baseline?(path, trusted_source, current_source)
  end

  def approved_ios_measurement_addition?(path, current_source)
    fingerprint = IOS_MEASUREMENT_NEW_SHA256[path]
    (fingerprint && Digest::SHA256.hexdigest(current_source) == fingerprint) ||
      approved_pinned_baseline_addition?(path, current_source) ||
      approved_aurora_change?(path, current_source) ||
      approved_aurora_addition?(path, current_source) ||
      approved_luma_change?(path, current_source) ||
      approved_luma_addition?(path, current_source)
  end

  def test_ios_measurement_existing_fingerprints_reject_unreviewed_bytes_and_paths
    IOS_MEASUREMENT_SOURCE_SHA256.each_key do |path|
      trusted = git("show", "#{BASELINE}:#{path}")
      current = File.binread(File.join(ROOT, path))
      assert approved_ios_measurement_change?(path, trusted, current), path
      refute approved_ios_measurement_change?(path, trusted + " ", current), path
      refute approved_ios_measurement_change?(path, trusted, current + " "), path
      refute approved_ios_measurement_change?("lib/features/proxy/active/unreviewed.dart", trusted, current)
    end
  end

  def test_ios_measurement_new_fingerprints_reject_unreviewed_bytes_and_paths
    IOS_MEASUREMENT_NEW_SHA256.each_key do |path|
      current = File.binread(File.join(ROOT, path))
      assert approved_ios_measurement_addition?(path, current), path
      refute approved_ios_measurement_addition?(path, current + " "), path
      refute approved_ios_measurement_addition?("lib/features/proxy/active/unreviewed.dart", current)
    end
    refute allowed_addition?("lib/features/proxy/active/unreviewed.dart")
    refute allowed_addition?("lib/features/proxy/active/ios_active_proxy_measurement_extra.dart")
    refute allowed_addition?("lib/features/proxy/active/ios_active_proxy_measurement.dart/extra.dart")
  end

  def test_new_diagnostic_sources_match_reviewed_fingerprints
    assert_equal DIAGNOSTIC_NEW_FILES.sort, DIAGNOSTIC_NEW_SHA256.keys.sort
    DIAGNOSTIC_NEW_SHA256.each do |path, expected|
      current = File.binread(File.join(ROOT, path))
      assert expected == Digest::SHA256.hexdigest(current) ||
        approved_pinned_baseline_addition?(path, current) ||
        approved_aurora_change?(path, current) ||
        approved_current_patch_change?(path, current) ||
        approved_luma_change?(path, current), path
    end
  end

  def approved_diagnostic_change?(path, trusted_source, current_source)
    fingerprints = DIAGNOSTIC_SOURCE_SHA256[path]
    (fingerprints &&
      Digest::SHA256.hexdigest(trusted_source) == fingerprints.fetch(0) &&
      Digest::SHA256.hexdigest(current_source) == fingerprints.fetch(1)) ||
      approved_pinned_baseline_change?(path, trusted_source, current_source) ||
      approved_aurora_change?(path, current_source) ||
      approved_current_patch_change_from_baseline?(path, trusted_source, current_source) ||
      approved_luma_change_from_baseline?(path, trusted_source, current_source)
  end

  def test_diagnostic_fingerprints_reject_unreviewed_bytes_and_paths
    assert_equal DIAGNOSTIC_EXISTING_FILES.sort, DIAGNOSTIC_SOURCE_SHA256.keys.sort
    DIAGNOSTIC_SOURCE_SHA256.each do |path, _|
      trusted = git("show", "#{BASELINE}:#{path}")
      current = File.binread(File.join(ROOT, path))
      assert approved_diagnostic_change?(path, trusted, current), path
      refute approved_diagnostic_change?(path, trusted, current + " "), path
      refute approved_diagnostic_change?(path, trusted + " ", current), path
      refute approved_diagnostic_change?("ios/Runner/Unapproved.swift", trusted, current)
    end
  end

  def test_diagnostics_do_not_allow_vpn_policy_identity_or_pipeline_changes
    %w[
      lib/features/connection/data/connection_repository.dart
      lib/features/connection/notifier/connection_notifier.dart
      lib/hiddifycore/hiddify_core_service.dart
      ios/Runner/VPN/MethodHandler.swift
      ios/Runner/Info.plist
      ios/Runner/Runner.entitlements
      .github/workflows/ios-baseline.yml
      pubspec.yaml pubspec.lock
    ].each do |path|
      refute DIAGNOSTIC_SOURCE_SHA256.key?(path), path
      refute DIAGNOSTIC_NEW_FILES.include?(path), path
      refute approved_diagnostic_change?(path, "old", "new"), path
    end
    refute allowed_addition?("lib/features/diagnostics/unreviewed.dart")
  end

  def git(*args)
    output, status = Open3.capture2("git", "-C", ROOT, *args)
    assert status.success?, "Git read failed: #{args.first}"
    output
  end

  def allowed_ui?(path)
    UI_FILES.include?(path) || UI_PREFIXES.any? { |prefix| path.start_with?(prefix) }
  end

  def approved_protected_change?(path, trusted_source, current_source)
    approved_log_removal = trusted_source.sub(APPROVED_RAW_LOG_LINE, "")
    path == PROFILE_DETAILS_NOTIFIER &&
      trusted_source.scan(APPROVED_RAW_LOG_LINE).length == 1 &&
      trusted_source.scan(TRUSTED_PARSE_ERROR_LINE).length == 1 &&
      [
        approved_log_removal,
        approved_log_removal.sub(TRUSTED_PARSE_ERROR_LINE, APPROVED_PARSE_ERROR_LINE),
      ].include?(current_source)
  end

  def trusted_profile_details_notifier
    git("show", "#{BASELINE}:#{PROFILE_DETAILS_NOTIFIER}")
  end

  def approved_profile_details_notifier
    trusted_profile_details_notifier.sub(APPROVED_RAW_LOG_LINE, "")
  end

  def approved_private_profile_details_notifier
    approved_profile_details_notifier.sub(TRUSTED_PARSE_ERROR_LINE, APPROVED_PARSE_ERROR_LINE)
  end

  def test_exact_profile_raw_log_removal_is_approved
    assert approved_protected_change?(
      PROFILE_DETAILS_NOTIFIER,
      trusted_profile_details_notifier,
      approved_profile_details_notifier,
    )
  end

  def test_exact_profile_raw_log_removal_and_safe_parse_error_replacement_is_approved
    assert approved_protected_change?(
      PROFILE_DETAILS_NOTIFIER,
      trusted_profile_details_notifier,
      approved_private_profile_details_notifier,
    )
  end

  def test_profile_raw_log_removal_is_not_approved_for_another_file
    refute approved_protected_change?(
      "lib/features/profile/details/profile_details_state.dart",
      trusted_profile_details_notifier,
      approved_profile_details_notifier,
    )
  end

  def test_profile_raw_log_removal_with_an_extra_body_change_is_rejected
    unsafe = approved_profile_details_notifier.sub("import 'dart:convert';", "import 'dart:async';")
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_safe_parse_error_replacement_with_an_extra_body_change_is_rejected
    unsafe = approved_private_profile_details_notifier.sub("import 'dart:convert';", "import 'dart:async';")
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_original_profile_raw_log_is_rejected
    refute approved_protected_change?(
      PROFILE_DETAILS_NOTIFIER,
      trusted_profile_details_notifier,
      trusted_profile_details_notifier,
    )
  end

  def test_relocated_profile_raw_log_is_rejected
    unsafe = approved_profile_details_notifier + APPROVED_RAW_LOG_LINE
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_replaced_profile_raw_log_is_rejected
    unsafe = trusted_profile_details_notifier.sub(APPROVED_RAW_LOG_LINE, "      loggy.debug(profContent);\n")
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_duplicated_profile_raw_log_is_rejected
    unsafe = trusted_profile_details_notifier.sub(APPROVED_RAW_LOG_LINE, APPROVED_RAW_LOG_LINE * 2)
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_reintroduced_raw_parse_error_is_rejected_from_safe_variant
    unsafe = approved_private_profile_details_notifier + TRUSTED_PARSE_ERROR_LINE
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_parse_error_to_string_is_rejected
    unsafe = approved_profile_details_notifier.sub(
      TRUSTED_PARSE_ERROR_LINE,
      "      loggy.error('Error parsing profile-content JSON (${e.toString()})', null, st);\n",
    )
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_parse_error_message_is_rejected
    unsafe = approved_profile_details_notifier.sub(
      TRUSTED_PARSE_ERROR_LINE,
      "      loggy.error('Error parsing profile-content JSON (${e.message})', null, st);\n",
    )
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_safe_parse_error_with_altered_stack_is_rejected
    unsafe = approved_profile_details_notifier.sub(
      TRUSTED_PARSE_ERROR_LINE,
      "      loggy.error('Error parsing profile-content JSON (${e.runtimeType})', null, StackTrace.current);\n",
    )
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_safe_parse_error_without_stack_is_rejected
    unsafe = approved_profile_details_notifier.sub(
      TRUSTED_PARSE_ERROR_LINE,
      "      loggy.error('Error parsing profile-content JSON (${e.runtimeType})', null);\n",
    )
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_relocated_safe_parse_error_is_rejected
    unsafe = approved_profile_details_notifier.sub(TRUSTED_PARSE_ERROR_LINE, "") + APPROVED_PARSE_ERROR_LINE
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_duplicated_safe_parse_error_is_rejected
    unsafe = approved_profile_details_notifier.sub(TRUSTED_PARSE_ERROR_LINE, APPROVED_PARSE_ERROR_LINE * 2)
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_changed_trusted_raw_log_multiplicity_is_rejected
    changed_trusted_source = trusted_profile_details_notifier.sub(
      APPROVED_RAW_LOG_LINE,
      APPROVED_RAW_LOG_LINE * 2,
    )
    candidate = changed_trusted_source.sub(APPROVED_RAW_LOG_LINE, "")
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, changed_trusted_source, candidate)
  end

  def test_missing_trusted_parse_error_line_is_rejected
    changed_trusted_source = trusted_profile_details_notifier.sub(TRUSTED_PARSE_ERROR_LINE, "")
    candidate = changed_trusted_source.sub(APPROVED_RAW_LOG_LINE, "")
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, changed_trusted_source, candidate)
  end

  def test_repeated_trusted_parse_error_line_is_rejected
    changed_trusted_source = trusted_profile_details_notifier.sub(
      TRUSTED_PARSE_ERROR_LINE,
      TRUSTED_PARSE_ERROR_LINE * 2,
    )
    candidate = changed_trusted_source.sub(APPROVED_RAW_LOG_LINE, "")
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, changed_trusted_source, candidate)
  end

  def test_any_additional_byte_in_approved_profile_source_is_rejected
    unsafe = approved_profile_details_notifier + " "
    refute approved_protected_change?(PROFILE_DETAILS_NOTIFIER, trusted_profile_details_notifier, unsafe)
  end

  def test_all_existing_runtime_native_identity_and_pipeline_files_outside_ui_are_unchanged
    paths = git("ls-tree", "-r", "--name-only", BASELINE).lines.map(&:strip)
    protected_paths = paths.select do |path|
      !path.start_with?("docs/", "test/") && !allowed_ui?(path) && !%w[pubspec.yaml pubspec.lock].include?(path)
    end
    changed = git("diff", "--name-only", BASELINE, "--", *protected_paths).lines.map(&:strip)
    changed.reject! do |path|
      current_path = File.join(ROOT, path)
      File.file?(current_path) &&
        (approved_protected_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_diagnostic_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_ios_measurement_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_ios_startup_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_native_glass_host_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_release_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_pinned_baseline_change?(path, git("show", "#{BASELINE}:#{path}"), File.binread(current_path)) ||
         approved_aurora_change?(path, File.binread(current_path)) ||
         approved_luma_change_from_baseline?(
           path,
           git("show", "#{BASELINE}:#{path}"),
           File.binread(current_path),
         ) ||
         approved_current_patch_change_from_baseline?(
           path,
           git("show", "#{BASELINE}:#{path}"),
           File.binread(current_path),
         ))
    end
    assert_empty changed, "Protected runtime/native/dependency/identity files changed: #{changed.join(', ')}"
  end

  # Test hosts are created outside the repository; only their reviewed runners
  # and integration entry point may be added here. No blanket scripts allowance.
  NEW_TOOL_FILES = %w[scripts/blizzard_prepare_test_host.py scripts/blizzard_simulator_run.py
                     scripts/ui_test_simulator_id.py integration_test/blizzard_home_particles_test.dart
                     integration_test/blizzard_preservation_test.dart integration_test/blizzard_v3_geometry_test.dart].freeze

  def allowed_addition?(path)
    path == "assets/images/blizzard_wave_envelope.png" || path.start_with?("test/", "docs/") || NEW_TOOL_FILES.include?(path) || path == NATIVE_GLASS_FILE ||
      DIAGNOSTIC_NEW_FILES.include?(path) || RELEASE_NEW_SHA256.key?(path) ||
      IOS_MEASUREMENT_NEW_SHA256.key?(path) || IOS_STARTUP_NEW_SHA256.key?(path) || NEW_UI_FILES.include?(path) ||
      AURORA_NEW_SHA256.key?(path) || CURRENT_PATCH_SOURCE_SHA256.key?(path) || CURRENT_PATCH_NEW_SHA256.key?(path) ||
      LUMA_NEW_SHA256.key?(path)
  end

  def unexpected_additions(current, baseline)
    (current - baseline).uniq.reject { |path| allowed_addition?(path) }
  end

  def test_new_repository_files_are_only_explicitly_approved
    paths = git("ls-files", "--cached", "--others", "--exclude-standard").lines.map(&:strip)
    old = git("ls-tree", "-r", "--name-only", BASELINE).lines.map(&:strip)
    unexpected = unexpected_additions(paths, old)
    unexpected.reject! do |path|
      current_path = File.join(ROOT, path)
      File.file?(current_path) &&
        (approved_pinned_baseline_addition?(path, File.binread(current_path)) ||
         approved_aurora_change?(path, File.binread(current_path)) ||
         approved_aurora_addition?(path, File.binread(current_path)))
    end
    assert_empty unexpected, "Unexpected new repository files: #{unexpected.join(', ')}"
  end

  def test_new_native_and_workflow_additions_are_detected
    old = %w[lib/main.dart ios/Runner/AppDelegate.swift]
    additions = %w[ios/Runner/Unapproved.swift .github/workflows/unapproved.yml]
    assert_equal additions, unexpected_additions(old + additions, old)
    assert_empty unexpected_additions(old + %w[test/new_test.dart docs/evidence.json] + NEW_TOOL_FILES, old)
    refute allowed_addition?("scripts/arbitrary-release.py")
    refute allowed_addition?("integration_test/ios/Runner/AppDelegate.swift")
    refute allowed_addition?("lib/features/profile/notifier/new_runtime.dart")
  end

  def test_runtime_dependency_declarations_and_sdk_constraints_are_identical
    before = YAML.safe_load(git("show", "#{BASELINE}:pubspec.yaml"))
    after = YAML.safe_load(File.read(File.join(ROOT, "pubspec.yaml")))
    %w[name environment dependencies dependency_overrides].each do |key|
      assert_equal before[key], after[key], "Changed runtime manifest field: #{key}"
    end
    expected_flutter = Marshal.load(Marshal.dump(before.fetch("flutter")))
    expected_flutter.fetch("assets").unshift("assets/images/blizzard_wave_envelope.png")
    expected_flutter["shaders"] = [
      "assets/shaders/blizzard_aurora.frag",
      "assets/shaders/blizzard_aurora_soft.frag",
    ]
    assert_equal expected_flutter, after.fetch("flutter"), "Only the two reviewed Aurora shaders may be added"
    assert_equal "5bca6e7c672919e0bc63f30e5048816f6285869b97a5b92e382e00f16bf6d3ea", Digest::SHA256.file(File.join(ROOT, "assets/images/blizzard_wave_envelope.png")).hexdigest
    delta = after.fetch("dev_dependencies").keys - before.fetch("dev_dependencies").keys
    assert_equal %w[flutter_test integration_test], delta.sort
    before.fetch("dev_dependencies").each do |key, value|
      assert_equal value, after.fetch("dev_dependencies")[key], "Existing dev tool changed: #{key}"
    end
  end

  def test_aurora_manifest_delta_adds_only_the_reviewed_shader
    before = YAML.safe_load(git("show", "#{AURORA_BASELINE}:pubspec.yaml"))
    after = YAML.safe_load(git("show", "#{CURRENT_PATCH_BASE}:pubspec.yaml"))
    expected = Marshal.load(Marshal.dump(before))
    refute expected.fetch("flutter").key?("shaders")
    expected.fetch("flutter")["shaders"] = ["assets/shaders/blizzard_aurora.frag"]

    assert_equal expected, after
  end

  def test_luma_manifest_delta_adds_only_the_second_reviewed_shader
    before = YAML.safe_load(git("show", "#{LUMA_BASELINE}:pubspec.yaml"))
    after = YAML.safe_load(File.read(File.join(ROOT, "pubspec.yaml")))
    expected = Marshal.load(Marshal.dump(before))
    assert_equal ["assets/shaders/blizzard_aurora.frag"], expected.fetch("flutter").fetch("shaders")
    expected.fetch("flutter")["shaders"] = [
      "assets/shaders/blizzard_aurora.frag",
      "assets/shaders/blizzard_aurora_soft.frag",
    ]

    assert_equal expected, after
  end

  def test_existing_resolved_packages_do_not_upgrade_and_additions_are_test_only
    before = YAML.safe_load(git("show", "#{BASELINE}:pubspec.lock"))
    after = YAML.safe_load(File.read(File.join(ROOT, "pubspec.lock")))
    before.fetch("packages").each do |name, package|
      actual = after.fetch("packages")[name]
      refute_nil actual, "Removed resolved package: #{name}"
      expected = package.dup
      expected["dependency"] = "direct dev" if name == "flutter_test"
      assert_equal expected, actual, "Changed resolved package: #{name}"
    end
    assert_equal DEV_ADDITIONS.sort, (after.fetch("packages").keys - before.fetch("packages").keys).sort
    assert_equal before.fetch("sdks"), after.fetch("sdks")
  end

  def test_hydrated_core_framework_matches_baseline_bytes
    receipt = JSON.parse(File.read(File.join(ROOT, "docs/verification/blizzard/native-framework-hydration.json")))
    refute_empty receipt.fetch("files")
    receipt.fetch("files").each do |entry|
      path = File.join(ROOT, "ios/Frameworks/HiddifyCore.xcframework", entry.fetch("path"))
      assert File.file?(path), "Missing baseline core file"
      assert_equal entry.fetch("sha256"), Digest::SHA256.file(path).hexdigest, "Core artifact changed"
    end
  end
end
