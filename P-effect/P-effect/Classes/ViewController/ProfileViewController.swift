//
//  ProfileViewController.swift
//  P-effect
//
//  Created by Illya on 1/18/16.
//  Copyright © 2016 Yalantis. All rights reserved.
//

import UIKit
import Toast

final class ProfileViewController: UITableViewController, StoryboardInitable, NavigationControllerAppearanceContext {
    
    static let storyboardName = Constants.Storyboard.Profile
    private var router: protocol<EditProfilePresenter, FeedPresenter, FollowersListPresenter, AuthorizationPresenter, AlertManagerDelegate>!
    private var user: User? {
        didSet {
            updateSelf()
        }
    }
    private var userId: String?
    
    private weak var locator: ServiceLocator!
    private var activityShown: Bool?
    private lazy var postAdapter = PostAdapter()
    private lazy var settingsMenu = SettingsMenu()
    
    @IBOutlet private weak var profileSettingsButton: UIBarButtonItem!
    @IBOutlet private weak var userAvatar: UIImageView!
    @IBOutlet private weak var userName: UILabel!
    @IBOutlet private weak var tableViewFooter: UIView!
    
    @IBOutlet private weak var followersQuantity: UILabel!
    @IBOutlet private weak var followingQuantity: UILabel!
    @IBOutlet private weak var followButton: UIButton!
    
    @IBOutlet private weak var followButtonHeight: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupController()
        setupLoadersCallback()
        setupFollowButton()
        setupGestureRecognizers()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        AlertManager.sharedInstance.registerAlertListener(router)
    }
    
    // MARK: - Inner func
    func setLocator(locator: ServiceLocator) {
        self.locator = locator
    }
    
    func setUser(user: User) {
        self.user = user
    }
    
    func setUserId(userId: String) {
        self.userId = userId
        let userService: UserService = locator.getService()
        userService.fetchUser(userId) { [weak self] user, error in
            if let error = error {
                log.debug(error.localizedDescription)
            } else {
                self?.setUser(user)
            }
        }
    }
    
    func setRouter(router: ProfileRouter) {
        self.router = router
    }
    
    private func updateSelf() {
        setupFollowButton()
        setupController()
    }
    
    private func setupController() {
        showToast()
        tableView.dataSource = postAdapter
        postAdapter.delegate = self
        tableView.registerNib(PostViewCell.nib, forCellReuseIdentifier: PostViewCell.identifier)
        setupTableViewFooter()
        applyUser()
        loadUserPosts()
    }
    
    private func setupFollowButton() {
        guard let user = user else {
            return
        }
        followButton?.selected = false
        followButton?.enabled = false
        let cache = AttributesCache.sharedCache
        if let followStatus = cache.followStatusForUser(user) {
            followButton?.selected = followStatus
            followButton?.enabled = true
        } else {
            let activityService: ActivityService = locator.getService()
            activityService.checkIsFollowing(user) { [weak self] follow in
                self?.followButton?.selected = follow
                self?.followButton?.enabled = true
            }
        }
    }
    
    private func loadUserPosts() {
        guard let user = user else {
            return
        }
        let postService: PostService = locator.getService()
        postService.loadPosts(user) { [weak self] objects, error in
            guard let this = self else {
                return
            }
            if let objects = objects {
                this.postAdapter.update(withPosts: objects, action: .Reload)
                this.view.hideToastActivity()
            } else if let error = error {
                log.debug(error.localizedDescription)
            }
        }
    }
    
    private func setupTableViewFooter() {
        let screenSize = view.bounds
        var frame = tableViewFooter.frame
        if let navigationController = navigationController {
            frame.size.height = (screenSize.height - Constants.Profile.HeaderHeight - navigationController.navigationBar.frame.size.height)
        } else {
            frame.size.height = Constants.Profile.PossibleInsets
        }
        tableViewFooter.frame = frame
        tableView.tableFooterView = tableViewFooter
    }
    
    private func setupGestureRecognizers() {
        let followersGestureRecognizer = UITapGestureRecognizer(target: self, action: "didTapFollowersLabel:")
        followersQuantity.addGestureRecognizer(followersGestureRecognizer)
        
        let followingGestureRecognizer = UITapGestureRecognizer(target: self, action: "didTapFollowingLabel:")
        followingQuantity.addGestureRecognizer(followingGestureRecognizer)
    }
    
    private func applyUser() {
        userAvatar.layer.cornerRadius = Constants.Profile.AvatarImageCornerRadius
        userAvatar.image = UIImage(named: Constants.Profile.AvatarImagePlaceholderName)
        guard let user = user else {
            return
        }
        userName.text = user.username
        navigationItem.title = Constants.Profile.NavigationTitle
        
        guard let avatar = user.avatar else {
            return
        }
        
        ImageLoaderService.getImageForContentItem(avatar) { [weak self] image, error in
            guard let this = self else {
                return
            }
            if error == nil {
                this.userAvatar.image = image
            } else {
                this.view.makeToast(error?.localizedDescription)
            }
        }
        
        if user.isCurrentUser {
            profileSettingsButton.enabled = true
            profileSettingsButton.image = UIImage(named: Constants.Profile.SettingsButtonImage)
            profileSettingsButton.tintColor = UIColor.appWhiteColor

            followButton.hidden = true
            followButtonHeight.constant = 0.1
        }
        fillFollowersQuantity(user)
    }
    
    private func showToast() {
        let toastActivityHelper = ToastActivityHelper()
        toastActivityHelper.showToastActivityOn(view, duration: Constants.Profile.ToastActivityDuration)
        activityShown = true
    }
    
    private func setupLoadersCallback() {
        let postService: PostService = locator.getService()
        tableView.addPullToRefreshWithActionHandler { [weak self] in
            guard let this = self else {
                return
            }
            
            let reachabilityService: ReachabilityService = this.locator.getService()
            guard reachabilityService.isReachable() else {
                ExceptionHandler.handle(Exception.NoConnection)
                this.tableView.pullToRefreshView.stopAnimating()

                return
            }
                
            postService.loadPosts(this.user) { objects, error in
                if let objects = objects {
                    this.postAdapter.update(withPosts: objects, action: .Reload)
                    AttributesCache.sharedCache.clear()
                } else if let error = error {
                    log.debug(error.localizedDescription)
                }
                this.tableView.pullToRefreshView.stopAnimating()
            }
        }
        tableView.addInfiniteScrollingWithActionHandler { [weak self] in
            guard let this = self else {
                return
            }
            postService.loadPagedPosts(this.user, offset: this.postAdapter.postQuantity) { objects, error in
                if let objects = objects {
                    this.postAdapter.update(withPosts: objects, action: .LoadMore)
                } else if let error = error {
                    log.debug(error.localizedDescription)
                }
                this.tableView.infiniteScrollingView.stopAnimating()
            }
        }
    }
    
    private func toggleFollowFriend() {
        guard let user = user else {
            return
        }
        let activityService: ActivityService = locator.getService()
        if followButton.selected {
            // Unfollow
            followButton.enabled = false
            
            let alertController = UIAlertController(title: "Unfollow", message: "Are you sure you want to unfollow?", preferredStyle: .ActionSheet)
            let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { [weak self] _ in
                self?.followButton.enabled = true
            }
            
            let unfollowAction = UIAlertAction(title: "Yes", style: .Default) { [weak self] _ in
                guard let this = self, user = this.user else {
                    return
                }
                activityService.unfollowUserEventually(user) { [weak self] success, error in
                    if success {
                        self?.followButton.selected = false
                        self?.followButton.enabled = true
                    }
                }
            }
            
            alertController.addAction(cancelAction)
            alertController.addAction(unfollowAction)
            
            presentViewController(alertController, animated: true, completion: nil)
        } else {
            // Follow
            followButton.selected = true
            let indicator = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
            indicator.center = followButton.center
            indicator.hidesWhenStopped = true
            indicator.startAnimating()
            followButton.addSubview(indicator)
            activityService.followUserEventually(user) { succeeded, error in
                if error == nil {
                    log.debug("Attempt to follow was \(succeeded) ")
                    self.followButton.selected = true
                } else {
                    self.followButton.selected = false
                }
                indicator.removeFromSuperview()
            }
        }
    }
    
    private func fillFollowersQuantity(user: User) {
        let attributes = AttributesCache.sharedCache.attributesForUser(user)
        guard let followersQt = attributes?[Constants.Attributes.FollowersCount],
            folowingQt = attributes?[Constants.Attributes.FollowingCount] else {
                let activityService: ActivityService = locator.getService()
                activityService.fetchFollowersQuantity(user) { [weak self] followersCount, followingCount in
                    if let this = self {
                        this.followersQuantity.text = String(followersCount) + " followers"
                        this.followingQuantity.text = String(followingCount) + " following"
                    }
                }
                
                return
        }
        followersQuantity.text = String(followersQt) + " followers"
        followingQuantity.text = String(folowingQt) + " following"
    }
    
    // MARK: - IBActions
    @IBAction private func followSomeone() {
        let reachabilityService: ReachabilityService = locator.getService()
        guard reachabilityService.isReachable() else {
            ExceptionHandler.handle(Exception.NoConnection)
            
            return
        }
        if User.notAuthorized {
            let alertController = UIAlertController(title: "You can't follow someone without registration", message: "", preferredStyle: .Alert)
            let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
            
            let registerAction = UIAlertAction(title: "Register", style: .Default) { [weak self] _ in
                self?.router.showAuthorization()
            }
            
            alertController.addAction(cancelAction)
            alertController.addAction(registerAction)
            
            presentViewController(alertController, animated: true, completion: nil)
        } else {
            toggleFollowFriend()
        }
    }
    
    @IBAction private func profileSettings() {
        router.showEditProfile()
    }

    dynamic private func didTapFollowersLabel(recognizer: UIGestureRecognizer) {
        guard let user = user else {
            return
        }
        guard let followersQuantity = followersQuantity.text else {
            return
        }
        if followersQuantity[followersQuantity.startIndex] != "0" {
            router.showFollowersList(user, followType: .Followers)
        }
    }
    
    dynamic private func didTapFollowingLabel(recognizer: UIGestureRecognizer) {
        guard let user = user else {
            return
        }
        guard let followingQuantity = followingQuantity.text else {
            return
        }
        if followingQuantity[followingQuantity.startIndex] != "0" {
            router.showFollowersList(user, followType: .Following)
        }
    }
    
}

extension ProfileViewController: PostAdapterDelegate {
    
    func showSettingsMenu(adapter: PostAdapter, post: Post, index: Int, items: [AnyObject]) {
        settingsMenu.showInViewController(self, forPost: post, atIndex: index, items: items)
        settingsMenu.completionAuthorizeUser = { [weak self] in
            self?.router.showAuthorization()
        }
        
        settingsMenu.completionRemovePost = { [weak self] index in
            guard let this = self else {
                return
            }
            this.postAdapter.removePost(atIndex: index)
            this.tableView.reloadData()
        }
    }
    
    func showPlaceholderForEmptyDataSet(adapter: PostAdapter) {
        tableView.reloadData()
    }
    
    func postAdapterRequestedViewUpdate(adapter: PostAdapter) {
        tableView.reloadData()
    }
    
}

extension ProfileViewController {
    
    override func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        if activityShown == true {
            view.hideToastActivity()
            tableView.tableFooterView = nil
            tableView.scrollEnabled = true
        }
    }
    
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return tableView.bounds.size.width + PostViewCell.designedHeight
    }
    
}
