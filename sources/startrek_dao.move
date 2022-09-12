module movefuns::startrek_dao {
    use StarcoinFramework::DAOAccount;
    use StarcoinFramework::DAOSpace::{Self, CapType};
    use StarcoinFramework::AnyMemberPlugin::{Self, AnyMemberPlugin};
    use StarcoinFramework::InstallPluginProposalPlugin::{Self, InstallPluginProposalPlugin};
    use StarcoinFramework::Vector;
    use StarcoinFramework::Option;
    use StarcoinFramework::Signer;
    use StarcoinFramework::Errors;
    use StarcoinFramework::IdentifierNFT;
    use StarcoinFramework::Account;

    const ERR_NOT_GENESIS_MENTOR: u64 = 101;
    const ERR_MENBER_ALREADY: u64 = 102;
    const ERR_NOT_CANDIDATE: u64 = 103;
    const ERR_LEVEL_NOT_MATCH: u64 = 104;
    const ERR_INVALID_LEVEL: u64 = 105;
    const ERR_NOT_REACHABLE: u64 = 106;

    const NAME: vector<u8> = b"StarTrekDAO";

    struct StarTrekDAO has store, copy, drop {}

    struct StarTrekPlugin has store, drop {}

    struct GraduationCriteria has copy, store, drop {
        /// number of approvals from mentors for graduation.
        approvals: u64,
        /// amount of tokens for graduation award
        award: u128,
    }

    ///
    struct GraduationCertificate has key {
        level: u8,
    }

    /// Configurations for StarTrekDAO
    struct StarTrekConfig has copy, store, drop {
        genesis_mentors: vector<address>,
        /// graduation criteria for different level. The level is equal to index + 1.
        criterias: vector<GraduationCriteria>,
    }

    /// Proposal action for new mentor joning.
    struct MentorJoinAction<phantom TokenT: store> has copy, drop, store {
        candidate: address,
    }

    /// Proposal action for mentee graduation.
    struct MenteeGraduationAction<phantom TokenT: store> has copy, drop, store {
        mentee: address,
        level: u8,
    }

    /// directly upgrade the sender account to DAOAccount and create DAO with addresses of genesis mentors.
    public(script) fun create_dao_entry(
        sender: signer,
        image_data: vector<u8>,
        image_url: vector<u8>,
        description: vector<u8>,
        genesis_mentors: vector<address>,
        voting_delay: u64,
        voting_period: u64,
        voting_quorum_rate: u8,
        min_action_delay: u64,
        min_proposal_deposit: u128, ) {
        let dao_account_cap = DAOAccount::upgrade_to_dao(sender);

        let config = DAOSpace::new_dao_config(
            voting_delay,
            voting_period,
            voting_quorum_rate,
            min_action_delay,
            min_proposal_deposit,
        );
        let dao_root_cap = DAOSpace::create_dao<StarTrekDAO>(
            dao_account_cap,
            *&NAME,
            Option::some(image_data),
            Option::some(image_url),
            description,
            StarTrekDAO {},
            config
        );
        let witness = StarTrekPlugin {};
        let cap = DAOSpace::acquire_modify_config_cap<StarTrekDAO, StarTrekPlugin>(&witness);
        let config = default_config(genesis_mentors);
        DAOSpace::set_custom_config(&mut cap, config);

        DAOSpace::install_plugin_with_root_cap<StarTrekDAO, InstallPluginProposalPlugin>(&dao_root_cap, InstallPluginProposalPlugin::required_caps());
        DAOSpace::install_plugin_with_root_cap<StarTrekDAO, AnyMemberPlugin>(&dao_root_cap, AnyMemberPlugin::required_caps());

        DAOSpace::install_plugin_with_root_cap<StarTrekDAO, StarTrekPlugin>(&dao_root_cap, required_caps());
        DAOSpace::burn_root_cap(dao_root_cap);
    }

    public fun genesis_mentor_join(sender: &signer, image_data: Option::Option<vector<u8>>, image_url: Option::Option<vector<u8>>) {
        let addr = Signer::address_of(sender);
        assert!(!DAOSpace::is_member<StarTrekDAO>(addr), Errors::invalid_state(ERR_MENBER_ALREADY));
        let witness = StarTrekPlugin {};
        let config = DAOSpace::get_custom_config<StarTrekDAO, StarTrekConfig>();
        assert!(Vector::contains(&config.genesis_mentors, &addr), Errors::invalid_state(ERR_NOT_GENESIS_MENTOR));

        let cap = DAOSpace::acquire_member_cap<StarTrekDAO, StarTrekPlugin>(&witness);
        IdentifierNFT::accept<DAOSpace::DAOMember<StarTrekDAO>, DAOSpace::DAOMemberBody<StarTrekDAO>>(sender);
        DAOSpace::join_member<StarTrekDAO, StarTrekPlugin>(
            &cap,
            addr,
            image_data,
            image_url,
            1
        );
    }

    public(script) fun genesis_mentor_join_entry(sender: signer, image_data: vector<u8>, image_url: vector<u8>) {
        genesis_mentor_join(&sender, Option::some(image_data), Option::some(image_url));
    }

    public fun mentee_join(sender: &signer, image_data: Option::Option<vector<u8>>, image_url: Option::Option<vector<u8>>) {
        let addr = Signer::address_of(sender);
        assert!(!DAOSpace::is_member<StarTrekDAO>(addr), Errors::invalid_state(ERR_MENBER_ALREADY));
        let witness = StarTrekPlugin {};
        let cap = DAOSpace::acquire_member_cap<StarTrekDAO, StarTrekPlugin>(&witness);
        IdentifierNFT::accept<DAOSpace::DAOMember<StarTrekDAO>, DAOSpace::DAOMemberBody<StarTrekDAO>>(sender);
        DAOSpace::join_member<StarTrekDAO, StarTrekPlugin>(
            &cap,
            addr,
            image_data,
            image_url,
            0
        );
    }

    public(script) fun mentee_join_entry(sender: signer, image_data: vector<u8>, image_url: vector<u8>) {
        mentee_join(&sender, Option::some(image_data), Option::some(image_url))
    }

    public fun create_mentor_join_proposal<DAOT: store, TokenT: store>(sender: &signer, description: vector<u8>, candidate: address, action_delay: u64) {
        assert!(!DAOSpace::is_member<StarTrekDAO>(candidate), Errors::invalid_state(ERR_MENBER_ALREADY));
        let witness = StarTrekPlugin {};
        let cap = DAOSpace::acquire_proposal_cap<DAOT, StarTrekPlugin>(&witness);
        let action = MentorJoinAction<TokenT> {
            candidate,
        };
        DAOSpace::create_proposal(&cap, sender, action, description, action_delay);
    }

    public(script) fun create_mentor_join_proposal_entry<DAOT: store, TokenT: store>(sender: signer, description: vector<u8>, candidate: address, action_delay: u64) {
        create_mentor_join_proposal<DAOT, TokenT>(&sender, description, candidate, action_delay);
    }

    public fun execute_mentor_join_proposal<DAOT: store, TokenT: store>(sender: &signer, proposal_id: u64, image_data: Option::Option<vector<u8>>, image_url: Option::Option<vector<u8>>) {
        let witness = StarTrekPlugin {};
        let proposal_cap = DAOSpace::acquire_proposal_cap<DAOT, StarTrekPlugin>(&witness);
        let MentorJoinAction<TokenT> { candidate } = DAOSpace::execute_proposal<DAOT, StarTrekPlugin, MentorJoinAction<TokenT>>(&proposal_cap, sender, proposal_id);
        assert!(candidate == Signer::address_of(sender), Errors::invalid_state(ERR_NOT_CANDIDATE));

        let cap = DAOSpace::acquire_member_cap<StarTrekDAO, StarTrekPlugin>(&witness);
        IdentifierNFT::accept<DAOSpace::DAOMember<StarTrekDAO>, DAOSpace::DAOMemberBody<StarTrekDAO>>(sender);
        DAOSpace::join_member<StarTrekDAO, StarTrekPlugin>(
            &cap,
            candidate,
            image_data,
            image_url,
            1
        );
    }

    public(script) fun execute_mentor_join_proposal_entry<DAOT: store, TokenT: store>(sender: signer, proposal_id: u64, image_data: vector<u8>, image_url: vector<u8>) {
        execute_mentor_join_proposal<DAOT, TokenT>(&sender, proposal_id, Option::some(image_data), Option::some(image_url));
    }

    public fun create_mentee_graduation_proposal<DAOT: store, TokenT: store>(sender: &signer, graduation_level: u8, description: vector<u8>, action_delay: u64) {
        let mentee = Signer::address_of(sender);
        check_level_valid(graduation_level);

        let witness = StarTrekPlugin {};
        let cap = DAOSpace::acquire_proposal_cap<DAOT, StarTrekPlugin>(&witness);
        let action = MenteeGraduationAction<TokenT> {
            mentee,
            level: graduation_level,
        };
        DAOSpace::create_proposal(&cap, sender, action, description, action_delay);
    }

    public(script) fun create_mentee_graduation_proposal_entry<DAOT: store, TokenT: store>(sender: signer, graduation_level: u8, description: vector<u8>, action_delay: u64) {
        create_mentee_graduation_proposal<DAOT, TokenT>(&sender, graduation_level, description, action_delay);
    }

    public fun execute_mentee_graduation_proposal<DAOT: store, TokenT: store>(sender: &signer, proposal_id: u64)
    acquires GraduationCertificate {
        let witness = StarTrekPlugin {};
        let proposal_cap = DAOSpace::acquire_proposal_cap<DAOT, StarTrekPlugin>(&witness);
        let MenteeGraduationAction<TokenT> { mentee, level } = DAOSpace::execute_proposal<DAOT, StarTrekPlugin, MenteeGraduationAction<TokenT>>(
            &proposal_cap,
            sender,
            proposal_id,
        );
        assert!(mentee == Signer::address_of(sender), Errors::invalid_state(ERR_NOT_CANDIDATE));

        let token_cap = DAOSpace::acquire_withdraw_token_cap<DAOT, StarTrekPlugin>(&witness);
        let amount = compute_graduation_award_amount(mentee, level);
        let awards = DAOSpace::withdraw_token<DAOT, StarTrekPlugin, TokenT>(&token_cap, amount);
        Account::deposit_to_self<TokenT>(sender, awards);
        update_mentee_graduation_certificate(sender, level);
    }

    public(script) fun execute_mentee_graduation_proposal_entry<DAOT: store, TokenT: store>(sender: signer, proposal_id: u64)
    acquires GraduationCertificate {
        execute_mentee_graduation_proposal<DAOT, TokenT>(&sender, proposal_id);
    }

    fun check_level_valid(level: u8) {
        let level = (level as u64);
        let criterias = &DAOSpace::get_custom_config<StarTrekDAO, StarTrekConfig>().criterias;
        assert!(level >= 0 && level <= Vector::length(criterias), Errors::invalid_argument(ERR_INVALID_LEVEL));
    }

    fun compute_graduation_award_amount(mentee: address, level: u8): u128
    acquires GraduationCertificate {
        let criterias = &DAOSpace::get_custom_config<StarTrekDAO, StarTrekConfig>().criterias;
        let curr_level = if (!exists<GraduationCertificate>(mentee)) {
            0u8
        } else {
            borrow_global<GraduationCertificate>(mentee).level
        };
        let amount = 0u128;
        while (level > curr_level) {
            amount = amount + Vector::borrow(criterias, (level as u64) - 1).award;
            level = level - 1;
        };
        amount
    }

    fun update_mentee_graduation_certificate(sender: &signer, level: u8)
    acquires GraduationCertificate {
        let mentee = Signer::address_of(sender);
        if (!exists<GraduationCertificate>(mentee)) {
            move_to<GraduationCertificate>(sender, GraduationCertificate { level });
        } else {
            borrow_global_mut<GraduationCertificate>(mentee).level = level;
        }
    }

    fun default_config(genesis_mentors: vector<address>): StarTrekConfig {
        let criterias = Vector::empty<GraduationCriteria>();
        Vector::push_back(&mut criterias, GraduationCriteria {
            approvals: 3,
            award: 200,
        });
        Vector::push_back(&mut criterias, GraduationCriteria {
            approvals: 3,
            award: 300,
        });
        Vector::push_back(&mut criterias, GraduationCriteria {
            approvals: 3,
            award: 500,
        });
        StarTrekConfig {
            genesis_mentors,
            criterias,
        }
    }

    public fun required_caps(): vector<CapType> {
        let caps = Vector::singleton(DAOSpace::proposal_cap_type());
        Vector::push_back(&mut caps, DAOSpace::install_plugin_cap_type());
        Vector::push_back(&mut caps, DAOSpace::member_cap_type());
        Vector::push_back(&mut caps, DAOSpace::upgrade_module_cap_type());
        caps
    }

    public fun submit_upgrade_plan(package_hash: vector<u8>, version: u64, enforced: bool) {
        let witness = StarTrekPlugin {};
        let upgrade_cap = DAOSpace::acquire_upgrade_module_cap<StarTrekDAO, StarTrekPlugin>(&witness);
        DAOSpace::submit_upgrade_plan(&upgrade_cap, package_hash, version, enforced);
    }
}
